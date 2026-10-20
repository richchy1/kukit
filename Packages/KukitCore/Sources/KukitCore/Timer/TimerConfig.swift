import Foundation

public enum TimerKind: String, Codable, Sendable, CaseIterable {
    case pomodoro
    case stopwatch
}

public enum TimerPhase: String, Codable, Sendable {
    case focus
    case shortBreak
    case longBreak

    public var isBreak: Bool { self != .focus }
}

/// A timer technique: durations and rounds. Built-in presets live in code (so they never
/// get duplicated in a synced database); custom presets are stored by the app.
public struct TimerConfig: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: TimerKind
    public var focusMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    public var roundsBeforeLongBreak: Int
    public var isBuiltIn: Bool

    public static let focusRange = 1...240
    public static let shortBreakRange = 1...60
    public static let longBreakRange = 1...120
    public static let roundsRange = 2...10

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: TimerKind = .pomodoro,
        focusMinutes: Int,
        shortBreakMinutes: Int,
        longBreakMinutes: Int,
        roundsBeforeLongBreak: Int,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.roundsBeforeLongBreak = roundsBeforeLongBreak
        self.isBuiltIn = isBuiltIn
    }

    /// Returns a copy with every duration forced into its allowed range.
    public func clamped() -> TimerConfig {
        var copy = self
        copy.focusMinutes = min(max(focusMinutes, Self.focusRange.lowerBound), Self.focusRange.upperBound)
        copy.shortBreakMinutes = min(max(shortBreakMinutes, Self.shortBreakRange.lowerBound), Self.shortBreakRange.upperBound)
        copy.longBreakMinutes = min(max(longBreakMinutes, Self.longBreakRange.lowerBound), Self.longBreakRange.upperBound)
        copy.roundsBeforeLongBreak = min(max(roundsBeforeLongBreak, Self.roundsRange.lowerBound), Self.roundsRange.upperBound)
        return copy
    }

    public func duration(of phase: TimerPhase) -> TimeInterval? {
        guard kind == .pomodoro else { return nil }
        switch phase {
        case .focus: return TimeInterval(focusMinutes * 60)
        case .shortBreak: return TimeInterval(shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(longBreakMinutes * 60)
        }
    }

    /// Short description such as "25 / 5" or "Stopwatch".
    public var summary: String {
        switch kind {
        case .pomodoro: "\(focusMinutes) / \(shortBreakMinutes)"
        case .stopwatch: "Count up"
        }
    }

    // MARK: Built-in presets

    public static let classic = TimerConfig(
        id: "builtin.classic", name: "Classic",
        focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15,
        roundsBeforeLongBreak: 4, isBuiltIn: true
    )

    public static let deepWork = TimerConfig(
        id: "builtin.deepwork", name: "Deep Work",
        focusMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 20,
        roundsBeforeLongBreak: 3, isBuiltIn: true
    )

    public static let stopwatch = TimerConfig(
        id: "builtin.stopwatch", name: "Stopwatch", kind: .stopwatch,
        focusMinutes: 0, shortBreakMinutes: 0, longBreakMinutes: 0,
        roundsBeforeLongBreak: 0, isBuiltIn: true
    )

    public static let builtIns: [TimerConfig] = [.classic, .deepWork, .stopwatch]
}

public struct TimerOptions: Codable, Equatable, Sendable {
    /// Start the next phase automatically when one ends (breaks and focus rounds).
    public var autoStartNext: Bool
    /// Focus runs shorter than this are discarded instead of saved.
    public var minimumSessionSeconds: TimeInterval

    public init(autoStartNext: Bool = true, minimumSessionSeconds: TimeInterval = 60) {
        self.autoStartNext = autoStartNext
        self.minimumSessionSeconds = minimumSessionSeconds
    }
}
