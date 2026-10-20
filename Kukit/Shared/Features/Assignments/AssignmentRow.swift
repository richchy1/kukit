import SwiftUI
import SwiftData
import KukitCore

extension Assignment {
    var dueBucket: DueBucket {
        DueBucket.bucket(due: dueDate, hasTime: hasDueTime, now: .now)
    }

    var isOverdue: Bool { !isDone && dueBucket == .overdue }

    /// "Today 23:59", "Tomorrow", "Mon, Oct 23" …
    var dueDescription: String? {
        guard let dueDate else { return nil }
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(dueDate) {
            day = "Today"
        } else if calendar.isDateInTomorrow(dueDate) {
            day = "Tomorrow"
        } else if calendar.isDateInYesterday(dueDate) {
            day = "Yesterday"
        } else {
            day = dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        guard hasDueTime else { return day }
        return "\(day) \(dueDate.formatted(date: .omitted, time: .shortened))"
    }

    /// Open tasks first by due date (undated last), then by priority.
    static func sortedByUrgency(_ items: [Assignment]) -> [Assignment] {
        items.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.priorityRaw > b.priorityRaw
            }
        }
    }
}

struct AssignmentRow: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @Environment(AppRouter.self) private var router
    var assignment: Assignment
    var showsCourse = true
    var onEdit: () -> Void

    private var tint: Color { assignment.course?.color ?? Theme.accent }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                AssignmentActions.setDone(assignment, !assignment.isDone, context: context)
            } label: {
                Image(systemName: assignment.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(assignment.isDone ? tint : Color.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(assignment.isDone ? "Mark not done" : "Mark done")

            Button(action: onEdit) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(assignment.title)
                            .font(.body.weight(.medium))
                            .strikethrough(assignment.isDone)
                            .foregroundStyle(assignment.isDone ? .secondary : .primary)
                            .multilineTextAlignment(.leading)
                        subtitle
                    }
                    Spacer(minLength: 4)
                    if assignment.priority == .high && !assignment.isDone {
                        Image(systemName: "flag.fill").font(.caption).foregroundStyle(.orange)
                            .accessibilityLabel("High priority")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
            if !assignment.isDone, assignment.course != nil {
                Button("Focus on this", systemImage: "timer") { focus() }
            }
            Button(assignment.isDone ? "Mark not done" : "Mark done", systemImage: "checkmark.circle") {
                AssignmentActions.setDone(assignment, !assignment.isDone, context: context)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                AssignmentActions.delete(assignment, context: context)
            }
        }
    }

    private var subtitle: some View {
        HStack(spacing: 6) {
            if showsCourse, let course = assignment.course {
                Circle().fill(course.color).frame(width: 8, height: 8)
                Text(course.name)
            }
            Image(systemName: assignment.type.systemImage).imageScale(.small)
            if let due = assignment.dueDescription {
                Text("· \(due)")
                    .foregroundStyle(assignment.isOverdue ? Color.red : Color.secondary)
                    .fontWeight(assignment.isOverdue ? .semibold : .regular)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private func focus() {
        if let id = assignment.course?.id { timer.selectCourse(id) }
        timer.selectAssignment(assignment.id)
        router.section = .focus
    }
}

/// Multi-select list of "how long before" choices.
struct ReminderOffsetPicker: View {
    @Binding var offsets: Set<Int>

    var body: some View {
        ForEach(ReminderDefaults.choices, id: \.self) { minutes in
            Toggle(ReminderDefaults.label(minutes), isOn: Binding(
                get: { offsets.contains(minutes) },
                set: { isOn in
                    if isOn { offsets.insert(minutes) } else { offsets.remove(minutes) }
                }
            ))
        }
    }
}
