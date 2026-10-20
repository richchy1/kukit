import Foundation
import UserNotifications
import KukitCore

/// Schedules the local notifications that tell the user a phase has ended — including when
/// the app is closed or the phone is locked.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    struct Item: Sendable {
        var date: Date
        var title: String
        var body: String
    }

    private let center = UNUserNotificationCenter.current()
    private let prefix = "kukit.timer."

    override private init() {
        super.init()
        center.delegate = self
    }

    // MARK: Permission

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Asks once (the system only shows its prompt the first time). Returns whether alerts are allowed.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    // MARK: Scheduling

    /// Makes the pending timer notifications match `items`. Uses stable IDs so an alert that
    /// is about to fire is never cancelled by a refresh that happens at the same moment.
    func sync(_ items: [Item]) async {
        let now = Date.now
        var desired: [String: Item] = [:]
        for item in items where item.date > now {
            desired[identifier(for: item.date)] = item
        }

        let pending = await center.pendingNotificationRequests()
        let mine = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }

        let stale = mine.filter { id in
            guard desired[id] == nil else { return false }
            guard let fire = fireDate(from: id) else { return true }
            return fire > now.addingTimeInterval(5)
        }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        let existing = Set(mine)
        for (id, item) in desired where !existing.contains(id) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let interval = max(1, item.date.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    /// Makes the pending assignment reminders match `planned`. Content may have changed
    /// (a title edit), so every planned reminder is (re)added under its stable ID.
    func syncTasks(_ planned: [PlannedReminder]) async {
        let pending = await center.pendingNotificationRequests()
        let mine = Set(pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) })
        let stale = mine.subtracting(planned.map(\.id))
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }
        for item in planned {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: item.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    private func identifier(for date: Date) -> String {
        prefix + String(Int(date.timeIntervalSince1970))
    }

    private func fireDate(from identifier: String) -> Date? {
        guard let seconds = TimeInterval(identifier.dropFirst(prefix.count)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// While the app is open, still show the banner and play the sound.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
