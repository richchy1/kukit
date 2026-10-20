import Foundation
import Observation
import SwiftData
import KukitCore

/// Bridges the pure `TimerEngine` to the app: the real clock, SwiftData, notifications,
/// and persistence of the running state across launches.
@MainActor
@Observable
final class TimerController {
    private(set) var engine = TimerEngine()

    /// Remembered selections for the next session.
    private(set) var selectedPresetID: String
    private(set) var selectedCourseID: UUID?
    /// The task the next session will be attached to (cleared once a session starts).
    private(set) var selectedAssignmentID: UUID?
    /// "18:42" while a timer is active, refreshed once per second. Drives the Mac menu bar label,
    /// which must not use a TimelineView (that makes the status item re-layout in a loop).
    private(set) var clockText = ""

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let notifications = NotificationService.shared
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var activity: NSObjectProtocol?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        selectedPresetID = defaults.string(forKey: Prefs.lastPresetID) ?? TimerConfig.classic.id
        selectedCourseID = defaults.string(forKey: Prefs.lastCourseID).flatMap(UUID.init(uuidString:))
        restore()
    }

    var state: TimerState { engine.state }

    // MARK: Selection

    func selectPreset(_ config: TimerConfig) {
        selectedPresetID = config.id
        defaults.set(config.id, forKey: Prefs.lastPresetID)
    }

    func selectCourse(_ id: UUID?) {
        selectedCourseID = id
        defaults.set(id?.uuidString, forKey: Prefs.lastCourseID)
    }

    func selectAssignment(_ id: UUID?) {
        selectedAssignmentID = id
    }

    // MARK: Commands

    /// Starts a session for the selected course. A course is required.
    func start(config: TimerConfig) {
        guard let courseID = selectedCourseID else { return }
        refreshOptions()
        let context = TimerContext(courseID: courseID, assignmentID: selectedAssignmentID)
        selectedAssignmentID = nil
        let events = engine.start(config: config, context: context, now: .now)
        commit(events)
        Task { await notifications.requestAuthorizationIfNeeded(); syncAlerts() }
    }

    func pause() { refreshOptions(); commit(engine.pause(now: .now)) }
    func resume() { refreshOptions(); commit(engine.resume(now: .now)) }
    func skip() { refreshOptions(); commit(engine.skip(now: .now)) }
    func stop() { refreshOptions(); commit(engine.stop(now: .now)) }
    func startNext() { refreshOptions(); commit(engine.startNext(now: .now)) }

    func discard() {
        engine.discard()
        commit([])
    }

    /// Call when the app returns to the foreground or the Mac wakes.
    func refresh() {
        refreshOptions()
        commit(engine.advance(now: .now))
    }

    // MARK: Internals

    private func refreshOptions() {
        let minutes = defaults.double(forKey: Prefs.minimumSessionMinutes)
        engine.options = TimerOptions(
            autoStartNext: defaults.bool(forKey: Prefs.autoStartNext),
            minimumSessionSeconds: max(0, minutes) * 60
        )
    }

    private func restore() {
        refreshOptions()
        guard let data = defaults.data(forKey: Prefs.timerState),
              let saved = try? JSONDecoder().decode(TimerState.self, from: data) else { return }
        engine = TimerEngine(state: saved, options: engine.options)
        // If the end time passed while the app was closed, this logs the finished phase.
        commit(engine.advance(now: .now))
    }

    /// Applies the effects of a transition and keeps everything derived in sync.
    private func commit(_ events: [TimerEvent]) {
        for event in events {
            if case .focusRecorded(let record) = event { save(record) }
        }
        persist()
        syncAlerts()
        updateTicking()
        updateActivity()
        refreshClockText()
    }

    private func save(_ record: FocusRecord) {
        let course = record.context.courseID.flatMap { id -> Course? in
            let descriptor = FetchDescriptor<Course>(predicate: #Predicate { $0.id == id })
            return try? modelContext.fetch(descriptor).first
        }
        let session = StudySession(
            startedAt: record.startedAt, endedAt: record.endedAt, focusSeconds: record.focusSeconds,
            presetName: record.presetName, kind: record.kind,
            assignmentID: record.context.assignmentID, course: course
        )
        modelContext.insert(session)
        try? modelContext.save()
    }

    private func refreshClockText(at now: Date = .now) {
        let state = engine.state
        let text: String
        if !state.isActive {
            text = ""
        } else if let remaining = state.remaining(at: now) {
            text = DurationFormat.clock(remaining)
        } else {
            text = DurationFormat.clock(state.elapsed(at: now).rounded(.down))
        }
        if text != clockText { clockText = text }
    }

    private func persist() {
        if engine.state.isActive, let data = try? JSONEncoder().encode(engine.state) {
            defaults.set(data, forKey: Prefs.timerState)
        } else {
            defaults.removeObject(forKey: Prefs.timerState)
        }
    }

    private func syncAlerts() {
        let config = engine.state.config
        let items = engine.pendingAlerts(now: .now).map { alert in
            let text = AlertText.make(for: alert, config: config)
            return NotificationService.Item(date: alert.date, title: text.title, body: text.body)
        }
        Task { await notifications.sync(items) }
    }

    /// While running, check the clock twice a second so a phase boundary is handled promptly.
    private func updateTicking() {
        guard engine.state.status == .running else {
            tickTask?.cancel()
            tickTask = nil
            return
        }
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                let events = self.engine.advance(now: .now)
                if !events.isEmpty { self.commit(events) } else { self.refreshClockText() }
            }
        }
    }

    /// On the Mac, keep the system from napping the app while a timer is running.
    private func updateActivity() {
        #if os(macOS)
        if engine.state.status == .running {
            if activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(
                    options: .userInitiatedAllowingIdleSystemSleep,
                    reason: "Kukit focus timer is running"
                )
            }
        } else if let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
        #endif
    }
}

enum AlertText {
    static func make(for alert: PhaseAlert, config: TimerConfig) -> (title: String, body: String) {
        switch (alert.endingPhase, alert.upcomingPhase) {
        case (.focus, .longBreak):
            return ("Done cooking", "Great round! Take a \(config.longBreakMinutes)-minute break.")
        case (.focus, _):
            return ("Done cooking", "Nice work. Take a \(config.shortBreakMinutes)-minute break.")
        default:
            return ("Break's over", "Ready to cook the next round?")
        }
    }
}
