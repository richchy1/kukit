import Foundation

/// Per-device preferences and small bits of remembered state (UserDefaults).
/// Things a user would expect on every device belong in the SwiftData store instead.
enum Prefs {
    // Settings
    static let autoStartNext = "pref.autoStartNext"
    static let minimumSessionMinutes = "pref.minimumSessionMinutes"
    static let dailyGoalMinutes = "pref.dailyGoalMinutes"
    static let keepScreenAwake = "pref.keepScreenAwake"
    static let showMenuBar = "pref.showMenuBar"
    static let menuBarCountdown = "pref.menuBarCountdown"

    // Remembered state
    static let timerState = "state.timerState"
    static let lastPresetID = "state.lastPresetID"
    static let lastCourseID = "state.lastCourseID"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            autoStartNext: true,
            minimumSessionMinutes: 1,
            dailyGoalMinutes: 120,
            keepScreenAwake: true,
            showMenuBar: true,
            menuBarCountdown: true,
        ])
    }
}
