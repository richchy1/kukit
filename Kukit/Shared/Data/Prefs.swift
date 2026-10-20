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
    static let reminderOffsetsTask = "pref.reminderOffsets.task"
    static let reminderOffsetsExam = "pref.reminderOffsets.exam"
    static let allDayReminderHour = "pref.allDayReminderHour"
    static let musicEnabled = "pref.music.enabled"
    static let musicVolume = "pref.music.volume"
    static let musicMuted = "pref.music.muted"
    static let musicAutoStart = "pref.music.autoStart"
    static let musicResumeWithTimer = "pref.music.resumeWithTimer"
    static let chefHumor = "pref.chef.humor"

    // Remembered state
    static let timerState = "state.timerState"
    static let lastPresetID = "state.lastPresetID"
    static let lastCourseID = "state.lastCourseID"
    static let lastBackupDate = "state.lastBackupDate"
    static let onboardingDone = "state.onboardingDone"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            autoStartNext: true,
            minimumSessionMinutes: 1,
            dailyGoalMinutes: 120,
            keepScreenAwake: true,
            showMenuBar: true,
            menuBarCountdown: true,
            reminderOffsetsTask: "1440,120",
            reminderOffsetsExam: "4320,1440,120",
            allDayReminderHour: 9,
            musicEnabled: true,
            musicVolume: 0.6,
            musicMuted: false,
            musicAutoStart: true,
            musicResumeWithTimer: true,
            chefHumor: true,
        ])
    }
}

enum ReminderDefaults {
    static func offsets(isExam: Bool) -> [Int] {
        let key = isExam ? Prefs.reminderOffsetsExam : Prefs.reminderOffsetsTask
        let stored = UserDefaults.standard.string(forKey: key) ?? ""
        return parse(stored)
    }

    static func parse(_ text: String) -> [Int] {
        text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    static func format(_ offsets: [Int]) -> String {
        offsets.sorted(by: >).map(String.init).joined(separator: ",")
    }

    static var allDayHour: Int {
        let hour = UserDefaults.standard.integer(forKey: Prefs.allDayReminderHour)
        return (0...23).contains(hour) ? hour : 9
    }

    /// "1 day before, 2 hours before"
    static func describe(_ offsets: [Int]) -> String {
        guard !offsets.isEmpty else { return "No reminders" }
        return offsets.sorted(by: >).map(label).joined(separator: ", ")
    }

    static let choices: [Int] = [0, 30, 60, 120, 360, 1440, 2880, 4320, 10080]

    static func label(_ minutes: Int) -> String {
        if minutes == 0 { return "At due time" }
        if minutes < 60 { return "\(minutes) minutes before" }
        if minutes < 1440 {
            let hours = minutes / 60
            return "\(hours) hour\(hours == 1 ? "" : "s") before"
        }
        let days = minutes / 1440
        if days % 7 == 0 {
            let weeks = days / 7
            return "\(weeks) week\(weeks == 1 ? "" : "s") before"
        }
        return "\(days) day\(days == 1 ? "" : "s") before"
    }
}
