import Foundation

/// The timer state machine. Every method takes `now` explicitly, so behavior is
/// deterministic and testable; the app supplies the real clock.
///
/// Transitions (see docs/SPEC.md §2.2):
///
///     idle ──start──▶ running ◀──resume── paused
///     running ──phase time up──▶ running(next)   (auto-start on)
///                              ▶ awaitingStart   (auto-start off, or a gap too long)
///     running/paused ──skip──▶ next phase    ──stop──▶ idle    ──discard──▶ idle
public struct TimerEngine: Sendable {
    public private(set) var state: TimerState
    public var options: TimerOptions

    public init(state: TimerState = .idle, options: TimerOptions = TimerOptions()) {
        self.state = state
        self.options = options
    }

    // MARK: Commands

    /// Starts round 1 of `config` (or the stopwatch) from idle.
    @discardableResult
    public mutating func start(config: TimerConfig, context: TimerContext, now: Date) -> [TimerEvent] {
        guard state.status == .idle else { return [] }
        let config = config.kind == .pomodoro ? config.clamped() : config
        state = TimerState(
            status: .running, config: config, context: context, phase: .focus,
            round: 1, phaseStartedAt: now, runningSince: now, accumulated: 0
        )
        return [.phaseStarted(.focus)]
    }

    /// Starts the phase that is waiting after a phase ended.
    @discardableResult
    public mutating func startNext(now: Date) -> [TimerEvent] {
        guard state.status == .awaitingStart else { return [] }
        begin(state.phase, round: state.round, at: now, running: true)
        return [.phaseStarted(state.phase)]
    }

    @discardableResult
    public mutating func pause(now: Date) -> [TimerEvent] {
        guard state.status == .running else { return [] }
        state.accumulated = state.elapsed(at: now)
        state.runningSince = nil
        state.status = .paused
        return []
    }

    @discardableResult
    public mutating func resume(now: Date) -> [TimerEvent] {
        guard state.status == .paused else { return [] }
        state.runningSince = now
        state.status = .running
        return []
    }

    /// Moves to the next phase right away. Skipping a focus phase early saves the time so far.
    @discardableResult
    public mutating func skip(now: Date) -> [TimerEvent] {
        switch state.status {
        case .idle:
            return []
        case .awaitingStart:
            guard state.phase.isBreak else { return [] }
            let (phase, round) = Self.next(after: state.phase, round: state.round, config: state.config)
            begin(phase, round: round, at: now, running: false)
            return []
        case .running, .paused:
            guard !state.isStopwatch else { return [] }
            var events: [TimerEvent] = []
            if state.phase == .focus, let record = record(endedAt: now) {
                events.append(.focusRecorded(record))
            }
            let (phase, round) = Self.next(after: state.phase, round: state.round, config: state.config)
            begin(phase, round: round, at: now, running: true)
            events.append(.phaseStarted(phase))
            return events
        }
    }

    /// Ends the session. Focus time so far is saved if it reaches the minimum.
    @discardableResult
    public mutating func stop(now: Date) -> [TimerEvent] {
        guard state.isActive else { return [] }
        var events: [TimerEvent] = []
        if state.status != .awaitingStart, state.phase == .focus, let record = record(endedAt: now) {
            events.append(.focusRecorded(record))
        }
        state = .idle
        return events
    }

    /// Ends the session and saves nothing.
    public mutating func discard() {
        state = .idle
    }

    /// Call regularly and on launch/foreground. Finishes a phase whose end time has passed.
    ///
    /// Only one phase boundary is crossed per call: if the app was away for so long that the
    /// auto-started next phase is also over, the timer waits for the user instead of
    /// logging focus time nobody can vouch for.
    @discardableResult
    public mutating func advance(now: Date) -> [TimerEvent] {
        guard state.status == .running, let end = state.endDate, now >= end,
              let duration = state.phaseDuration else { return [] }

        var events: [TimerEvent] = [.phaseEnded(state.phase)]
        if state.phase == .focus, duration >= options.minimumSessionSeconds {
            events.append(.focusRecorded(FocusRecord(
                startedAt: state.phaseStartedAt, endedAt: end, focusSeconds: duration,
                presetName: state.config.name, kind: state.config.kind, context: state.context
            )))
        }

        let (nextPhase, nextRound) = Self.next(after: state.phase, round: state.round, config: state.config)
        if options.autoStartNext, let nextDuration = state.config.duration(of: nextPhase) {
            if now < end.addingTimeInterval(nextDuration) {
                begin(nextPhase, round: nextRound, at: end, running: true)
                events.append(.phaseStarted(nextPhase))
                return events
            }
            if nextPhase.isBreak {
                // The break is already over too; wait at the next focus round.
                let (phase, round) = Self.next(after: nextPhase, round: nextRound, config: state.config)
                begin(phase, round: round, at: now, running: false)
                return events
            }
        }
        begin(nextPhase, round: nextRound, at: now, running: false)
        return events
    }

    // MARK: Queries

    /// Notifications that should be pending right now: the end of the current phase and,
    /// with auto-start on, the end of the phase after it.
    public func pendingAlerts(now: Date) -> [PhaseAlert] {
        guard state.status == .running, let end = state.endDate else { return [] }
        let (next, nextRound) = Self.next(after: state.phase, round: state.round, config: state.config)
        var alerts = [PhaseAlert(date: end, endingPhase: state.phase, upcomingPhase: next)]
        if options.autoStartNext, let nextDuration = state.config.duration(of: next) {
            let (after, _) = Self.next(after: next, round: nextRound, config: state.config)
            alerts.append(PhaseAlert(date: end.addingTimeInterval(nextDuration), endingPhase: next, upcomingPhase: after))
        }
        return alerts.filter { $0.date > now }
    }

    /// The phase (and round) that follows `phase`.
    public static func next(after phase: TimerPhase, round: Int, config: TimerConfig) -> (TimerPhase, Int) {
        switch phase {
        case .focus:
            return round >= config.roundsBeforeLongBreak ? (.longBreak, round) : (.shortBreak, round)
        case .shortBreak:
            return (.focus, round + 1)
        case .longBreak:
            return (.focus, 1)
        }
    }

    // MARK: Helpers

    private mutating func begin(_ phase: TimerPhase, round: Int, at date: Date, running: Bool) {
        state.phase = phase
        state.round = round
        state.phaseStartedAt = date
        state.accumulated = 0
        state.runningSince = running ? date : nil
        state.status = running ? .running : .awaitingStart
    }

    private func record(endedAt: Date) -> FocusRecord? {
        var seconds = state.elapsed(at: endedAt)
        if let duration = state.phaseDuration { seconds = min(seconds, duration) }
        guard seconds >= options.minimumSessionSeconds, seconds > 0 else { return nil }
        return FocusRecord(
            startedAt: state.phaseStartedAt, endedAt: endedAt, focusSeconds: seconds,
            presetName: state.config.name, kind: state.config.kind, context: state.context
        )
    }
}
