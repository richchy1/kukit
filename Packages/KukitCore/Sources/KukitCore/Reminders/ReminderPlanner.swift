import Foundation

/// What the planner needs to know about an assignment.
public struct ReminderTask: Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var courseName: String
    public var isExam: Bool
    public var due: Date
    /// False for date-only tasks: reminders are then fired at a fixed morning hour.
    public var hasTime: Bool
    /// Minutes before the due moment (0 = at due time). For date-only tasks, whole days apply.
    public var offsets: [Int]

    public init(id: UUID, title: String, courseName: String, isExam: Bool,
                due: Date, hasTime: Bool, offsets: [Int]) {
        self.id = id
        self.title = title
        self.courseName = courseName
        self.isExam = isExam
        self.due = due
        self.hasTime = hasTime
        self.offsets = offsets
    }
}

public struct PlannedReminder: Equatable, Sendable, Identifiable {
    public var id: String
    public var taskID: UUID
    public var fireDate: Date
    public var title: String
    public var body: String
}

/// Turns assignments into the notifications that should be pending right now.
///
/// iOS keeps at most 64 pending local notifications per app, so only the soonest
/// `limit` reminders are planned; the app re-plans whenever data changes or it opens.
public struct ReminderPlanner: Sendable {
    public var calendar: Calendar
    public var allDayHour: Int
    public var limit: Int

    public static let identifierPrefix = "kukit.task."

    public init(calendar: Calendar = .current, allDayHour: Int = 9, limit: Int = 60) {
        self.calendar = calendar
        self.allDayHour = allDayHour
        self.limit = limit
    }

    public static func defaultOffsets(isExam: Bool) -> [Int] {
        isExam ? [3 * 1440, 1440, 120] : [1440, 120]
    }

    public func plan(_ tasks: [ReminderTask], now: Date) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []
        for task in tasks {
            var seen = Set<Date>()
            for offset in task.offsets.sorted(by: >) {
                guard let fire = fireDate(for: task, offsetMinutes: offset), fire > now else { continue }
                guard seen.insert(fire).inserted else { continue }
                planned.append(PlannedReminder(
                    id: "\(Self.identifierPrefix)\(task.id.uuidString).\(offset)",
                    taskID: task.id,
                    fireDate: fire,
                    title: task.courseName.isEmpty ? task.title : "\(task.courseName): \(task.title)",
                    body: Self.phrase(offsetMinutes: offset, hasTime: task.hasTime, isExam: task.isExam)
                ))
            }
        }
        planned.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(planned.prefix(limit))
    }

    func fireDate(for task: ReminderTask, offsetMinutes: Int) -> Date? {
        if task.hasTime {
            return task.due.addingTimeInterval(-TimeInterval(offsetMinutes) * 60)
        }
        let days = offsetMinutes / 1440
        let dueDay = calendar.startOfDay(for: task.due)
        guard let day = calendar.date(byAdding: .day, value: -days, to: dueDay) else { return nil }
        return calendar.date(bySettingHour: allDayHour, minute: 0, second: 0, of: day)
    }

    /// "Due in 2 hours", "Exam tomorrow", "Due today"…
    public static func phrase(offsetMinutes: Int, hasTime: Bool, isExam: Bool) -> String {
        let noun = isExam ? "Exam" : "Due"
        if hasTime {
            switch offsetMinutes {
            case ..<1: return isExam ? "Exam starts now" : "Due now"
            case 1..<60: return "\(noun) in \(offsetMinutes) min"
            case 60..<1440:
                let hours = offsetMinutes / 60
                return "\(noun) in \(hours) hour\(hours == 1 ? "" : "s")"
            default: break
            }
        }
        let days = offsetMinutes / 1440
        switch days {
        case 0: return isExam ? "Exam today" : "Due today"
        case 1: return "\(noun) tomorrow"
        default: return "\(noun) in \(days) days"
        }
    }
}
