import Foundation

/// What a focus run is attached to.
public struct TimerContext: Codable, Equatable, Sendable {
    public var courseID: UUID?
    public var assignmentID: UUID?

    public init(courseID: UUID? = nil, assignmentID: UUID? = nil) {
        self.courseID = courseID
        self.assignmentID = assignmentID
    }
}

/// A finished stretch of focus time, ready to be saved as a study session.
public struct FocusRecord: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    public var focusSeconds: TimeInterval
    public var presetName: String
    public var kind: TimerKind
    public var context: TimerContext

    public init(startedAt: Date, endedAt: Date, focusSeconds: TimeInterval,
                presetName: String, kind: TimerKind, context: TimerContext) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.focusSeconds = focusSeconds
        self.presetName = presetName
        self.kind = kind
        self.context = context
    }
}

/// Things the app reacts to after a timer transition.
public enum TimerEvent: Equatable, Sendable {
    case focusRecorded(FocusRecord)
    case phaseEnded(TimerPhase)
    case phaseStarted(TimerPhase)
}

/// A notification the app should have scheduled while the timer runs.
public struct PhaseAlert: Equatable, Sendable {
    public var date: Date
    public var endingPhase: TimerPhase
    public var upcomingPhase: TimerPhase

    public init(date: Date, endingPhase: TimerPhase, upcomingPhase: TimerPhase) {
        self.date = date
        self.endingPhase = endingPhase
        self.upcomingPhase = upcomingPhase
    }
}

/// The complete, persistable state of the timer. All time is derived from dates —
/// no tick counting — so it stays correct through sleep, suspension and relaunch.
public struct TimerState: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case idle
        case running
        case paused
        /// A phase finished and the next one is ready but waiting for the user.
        case awaitingStart
    }

    public var status: Status
    public var config: TimerConfig
    public var context: TimerContext
    public var phase: TimerPhase
    /// 1-based focus round inside the current cycle.
    public var round: Int
    /// Wall-clock moment the current phase first started (used as the session start).
    public var phaseStartedAt: Date
    /// Start of the current uninterrupted running segment; nil unless running.
    public var runningSince: Date?
    /// Running seconds already spent in this phase before `runningSince`.
    public var accumulated: TimeInterval

    public static let idle = TimerState(
        status: .idle, config: .classic, context: TimerContext(), phase: .focus,
        round: 1, phaseStartedAt: .distantPast, runningSince: nil, accumulated: 0
    )

    public init(status: Status, config: TimerConfig, context: TimerContext, phase: TimerPhase,
                round: Int, phaseStartedAt: Date, runningSince: Date?, accumulated: TimeInterval) {
        self.status = status
        self.config = config
        self.context = context
        self.phase = phase
        self.round = round
        self.phaseStartedAt = phaseStartedAt
        self.runningSince = runningSince
        self.accumulated = accumulated
    }

    public var isActive: Bool { status != .idle }
    public var isStopwatch: Bool { config.kind == .stopwatch }

    /// Planned length of the current phase; nil for the stopwatch.
    public var phaseDuration: TimeInterval? { config.duration(of: phase) }

    /// Seconds spent running in the current phase.
    public func elapsed(at now: Date) -> TimeInterval {
        guard let since = runningSince else { return accumulated }
        return accumulated + max(0, now.timeIntervalSince(since))
    }

    /// Seconds left in the current phase; nil for the stopwatch.
    public func remaining(at now: Date) -> TimeInterval? {
        guard let duration = phaseDuration else { return nil }
        if status == .awaitingStart { return duration }
        return max(0, duration - elapsed(at: now))
    }

    /// 0...1 progress of the current phase. The stopwatch loops once an hour.
    public func progress(at now: Date) -> Double {
        if let duration = phaseDuration, duration > 0 {
            if status == .awaitingStart { return 0 }
            return min(1, elapsed(at: now) / duration)
        }
        return elapsed(at: now).truncatingRemainder(dividingBy: 3600) / 3600
    }

    /// When the running phase will end; nil unless running a timed phase.
    public var endDate: Date? {
        guard status == .running, let since = runningSince, let duration = phaseDuration else { return nil }
        return since.addingTimeInterval(max(0, duration - accumulated))
    }
}
