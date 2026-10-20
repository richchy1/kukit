import Foundation
import EventKit
import KukitCore

/// One-way push to Apple Reminders (and a one-time Calendar entry for exams).
/// Nothing is ever read back from those apps. EventKit identifiers can differ per device,
/// so they are kept in a device-local map; the synced `addedToAppleReminders` flag only
/// records that the user asked for it.
@MainActor
final class EventKitService {
    static let shared = EventKitService()

    private let store = EKEventStore()
    private let defaults = UserDefaults.standard
    private let reminderMapKey = "eventkit.reminderIDs"

    // MARK: Reminders

    /// Brings Apple Reminders in line with `assignment`: creates/updates the reminder when
    /// the flag is on, removes it when off. A missing reminder or calendar event is only
    /// created when the user just switched that option on. Failures are silent here; the
    /// editor asks for access up front and shows the result.
    func sync(_ assignment: Assignment, createReminder: Bool, createCalendarEvent: Bool) async {
        if assignment.addedToAppleReminders {
            guard await hasRemindersAccess(request: createReminder) else { return }
            let existing = reminder(forAssignmentID: assignment.id)
            guard existing != nil || createReminder else { return }
            let reminder = existing ?? EKReminder(eventStore: store)
            if existing == nil { reminder.calendar = store.defaultCalendarForNewReminders() }
            fill(reminder, from: assignment)
            do {
                try store.save(reminder, commit: true)
                var map = reminderMap()
                map[assignment.id.uuidString] = reminder.calendarItemIdentifier
                defaults.set(map, forKey: reminderMapKey)
            } catch {}
        } else {
            await removeReminder(forAssignmentID: assignment.id)
        }

        if createCalendarEvent, assignment.addedToCalendar, assignment.type == .exam {
            await addExamToCalendar(assignment)
        }
    }

    func removeReminder(forAssignmentID id: UUID) async {
        guard reminderMap()[id.uuidString] != nil, await hasRemindersAccess(request: false) else { return }
        if let reminder = reminder(forAssignmentID: id) {
            try? store.remove(reminder, commit: true)
        }
        var map = reminderMap()
        map[id.uuidString] = nil
        defaults.set(map, forKey: reminderMapKey)
    }

    /// Asks for access now (used when the user flips the toggle). Returns whether it was granted.
    func requestRemindersAccess() async -> Bool {
        await hasRemindersAccess(request: true)
    }

    private func hasRemindersAccess(request: Bool) async -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return true
        case .notDetermined:
            guard request else { return false }
            return (try? await store.requestFullAccessToReminders()) ?? false
        default:
            return false
        }
    }

    private func reminderMap() -> [String: String] {
        defaults.dictionary(forKey: reminderMapKey) as? [String: String] ?? [:]
    }

    private func reminder(forAssignmentID id: UUID) -> EKReminder? {
        guard let identifier = reminderMap()[id.uuidString] else { return nil }
        return store.calendarItem(withIdentifier: identifier) as? EKReminder
    }

    private func fill(_ reminder: EKReminder, from assignment: Assignment) {
        reminder.title = assignment.title
        var notes = assignment.course?.name ?? ""
        if !assignment.details.isEmpty { notes += notes.isEmpty ? assignment.details : "\n\n\(assignment.details)" }
        reminder.notes = notes.isEmpty ? nil : notes
        reminder.isCompleted = assignment.isDone
        switch assignment.priority {
        case .high: reminder.priority = 1
        case .normal: reminder.priority = 5
        case .low: reminder.priority = 9
        }

        for alarm in reminder.alarms ?? [] { reminder.removeAlarm(alarm) }
        if let due = assignment.dueDate {
            let units: Set<Calendar.Component> = assignment.hasDueTime
                ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(units, from: due)
            if let task = ReminderScheduler.task(from: assignment),
               let next = ReminderPlanner(allDayHour: ReminderDefaults.allDayHour).plan([task], now: .now).first {
                reminder.addAlarm(EKAlarm(absoluteDate: next.fireDate))
            }
        } else {
            reminder.dueDateComponents = nil
        }
    }

    // MARK: Calendar (exams, create-once)

    /// Write-only access cannot read events back, so an exam is added once and never edited.
    private func addExamToCalendar(_ assignment: Assignment) async {
        guard let due = assignment.dueDate else { return }
        let granted: Bool
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly: granted = true
        case .notDetermined: granted = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        default: granted = false
        }
        guard granted, let calendar = store.defaultCalendarForNewEvents else { return }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = "\(assignment.course?.name ?? "Exam"): \(assignment.title)"
        event.isAllDay = !assignment.hasDueTime
        event.startDate = due
        event.endDate = assignment.hasDueTime ? due.addingTimeInterval(2 * 3600) : due
        try? store.save(event, span: .thisEvent, commit: true)
    }
}
