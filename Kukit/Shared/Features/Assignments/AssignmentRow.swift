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

/// The deadline label: urgency by icon and wording as well as color, so color is never the only cue.
struct DueChip: View {
    var assignment: Assignment

    var body: some View {
        if assignment.isDone {
            Chip(text: "Done", systemImage: "checkmark.circle.fill", tint: Theme.basilText)
        } else if let due = assignment.dueDescription {
            switch assignment.dueBucket {
            case .overdue:
                Chip(text: "Overdue · \(due)", systemImage: "exclamationmark.circle.fill", tint: Theme.accent, filled: true)
            case .today:
                Chip(text: due, systemImage: "clock.fill", tint: Theme.butter, filled: true, textColor: Color(hex: "3A2E00"))
            default:
                Chip(text: due, systemImage: "calendar", tint: Theme.ink.opacity(0.7))
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
        HStack(alignment: .top, spacing: 12) {
            Button {
                AssignmentActions.setDone(assignment, !assignment.isDone, context: context)
            } label: {
                Image(systemName: assignment.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(assignment.isDone ? Theme.basil : tint.opacity(0.85))
                    .symbolEffect(.bounce, value: assignment.isDone)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(assignment.isDone ? "Mark not done" : "Mark done")

            Button(action: onEdit) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(assignment.title)
                            .font(.kukit(.body, weight: .bold))
                            .strikethrough(assignment.isDone)
                            .foregroundStyle(assignment.isDone ? Color.secondary : Theme.ink)
                            .multilineTextAlignment(.leading)
                        subtitle
                    }
                    Spacer(minLength: 4)
                    if assignment.priority == .high && !assignment.isDone {
                        Chip(text: "High", systemImage: "flag.fill", tint: Theme.accentText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .hoverHighlight()
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
            if !assignment.isDone, assignment.course != nil {
                Button("Cook this", systemImage: "flame") { focus() }
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
            Image(systemName: assignment.type.systemImage)
                .imageScale(.small)
                .foregroundStyle(tint)
            if showsCourse, let course = assignment.course {
                Text(course.name).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(assignment.type.title).foregroundStyle(.secondary)
            }
            DueChip(assignment: assignment)
        }
        .font(.kukit(.caption, weight: .semibold))
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
