import Foundation
import SwiftData
import KukitCore

/// Keeps the pending assignment notifications in step with the data. Call `scheduleResync`
/// after any change; it is debounced, and also runs when the app becomes active.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()
    private var pending: Task<Void, Never>?

    func scheduleResync(_ context: ModelContext) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.resync(context)
        }
    }

    func resync(_ context: ModelContext) async {
        let descriptor = FetchDescriptor<Assignment>(
            predicate: #Predicate { $0.statusRaw != "done" && $0.remindersEnabled }
        )
        let assignments = (try? context.fetch(descriptor)) ?? []
        let planner = ReminderPlanner(allDayHour: ReminderDefaults.allDayHour)
        let planned = planner.plan(assignments.compactMap(Self.task(from:)), now: .now)
        await NotificationService.shared.syncTasks(planned)
    }

    static func task(from assignment: Assignment) -> ReminderTask? {
        guard let due = assignment.dueDate else { return nil }
        let isExam = assignment.type == .exam
        return ReminderTask(
            id: assignment.id, title: assignment.title,
            courseName: assignment.course?.name ?? "", isExam: isExam,
            due: due, hasTime: assignment.hasDueTime,
            offsets: assignment.customReminderOffsets ?? ReminderDefaults.offsets(isExam: isExam)
        )
    }
}

/// The one place that changes assignments, so reminders and Apple Reminders stay consistent.
@MainActor
enum AssignmentActions {
    static func setDone(_ assignment: Assignment, _ done: Bool, context: ModelContext) {
        assignment.status = done ? .done : .todo
        // A linked score is a guess until the task is done.
        if let entry = assignment.gradeEntry {
            entry.isPlanned = !done
            if done { entry.date = .now }
        }
        persist(assignment, context: context)
    }

    /// Save after edits. The `create…` flags are true only when the user just turned that
    /// Apple Reminders / Calendar toggle on in the editor.
    static func persist(_ assignment: Assignment, context: ModelContext,
                        createReminder: Bool = false, createCalendarEvent: Bool = false) {
        try? context.save()
        ReminderScheduler.shared.scheduleResync(context)
        if assignment.remindersEnabled && assignment.dueDate != nil {
            Task { await NotificationService.shared.requestAuthorizationIfNeeded() }
        }
        Task {
            await EventKitService.shared.sync(
                assignment, createReminder: createReminder, createCalendarEvent: createCalendarEvent
            )
        }
    }

    static func delete(_ assignment: Assignment, context: ModelContext) {
        let id = assignment.id
        context.delete(assignment)
        try? context.save()
        ReminderScheduler.shared.scheduleResync(context)
        Task { await EventKitService.shared.removeReminder(forAssignmentID: id) }
    }
}
