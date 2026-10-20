import Foundation

/// The part of the timer state that decides what the background music should do.
public struct TimerSnapshot: Equatable, Sendable {
    public var status: TimerState.Status
    public var phase: TimerPhase

    public init(status: TimerState.Status, phase: TimerPhase) {
        self.status = status
        self.phase = phase
    }

    public init(_ state: TimerState) {
        self.init(status: state.status, phase: state.phase)
    }

    public static let idle = TimerSnapshot(status: .idle, phase: .focus)

    var isFocusRunning: Bool { status == .running && phase == .focus }
    var isFocusPaused: Bool { status == .paused && phase == .focus }
    var isFocusActive: Bool { isFocusRunning || isFocusPaused }
}

public enum MusicAction: Equatable, Sendable {
    case start      // begin the track from the beginning
    case pause
    case resume
    case stop
    case none
}

public struct MusicPolicy: Equatable, Sendable {
    public var isEnabled: Bool
    public var autoStart: Bool
    public var resumeWithTimer: Bool

    public init(isEnabled: Bool = true, autoStart: Bool = true, resumeWithTimer: Bool = true) {
        self.isEnabled = isEnabled
        self.autoStart = autoStart
        self.resumeWithTimer = resumeWithTimer
    }
}

public enum FocusMusic {
    /// What the music should do when the timer moves from `old` to `new`.
    ///
    /// Music belongs to *focus* time only: it starts with a focus phase, pauses and resumes with
    /// it, and stops when the session ends, is cancelled, or turns into a break.
    public static func action(from old: TimerSnapshot, to new: TimerSnapshot, policy: MusicPolicy) -> MusicAction {
        guard old != new else { return .none }

        if new.isFocusRunning {
            if old.isFocusPaused {
                return policy.isEnabled && policy.resumeWithTimer ? .resume : .none
            }
            if old.isFocusRunning { return .none }
            return policy.isEnabled && policy.autoStart ? .start : .none
        }

        if new.isFocusPaused {
            return old.isFocusRunning ? .pause : .none
        }

        // Idle, a break, or a phase waiting for the user: nothing should be playing.
        return old.isFocusActive ? .stop : .none
    }
}
