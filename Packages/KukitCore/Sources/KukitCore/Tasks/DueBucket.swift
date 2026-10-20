import Foundation

/// Where an assignment sits relative to now, for grouping lists.
public enum DueBucket: Int, CaseIterable, Comparable, Sendable {
    case overdue, today, nextSevenDays, later, noDate

    public static func < (lhs: DueBucket, rhs: DueBucket) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .nextSevenDays: "Next 7 days"
        case .later: "Later"
        case .noDate: "No date"
        }
    }

    /// - Parameters:
    ///   - hasTime: when false the task is due "any time that day" and only the day matters.
    public static func bucket(due: Date?, hasTime: Bool, now: Date, calendar: Calendar = .current) -> DueBucket {
        guard let due else { return .noDate }
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: due)
        if hasTime, due < now, dueDay >= today {
            // Due earlier today: already past.
            return .overdue
        }
        if dueDay < today { return .overdue }
        if dueDay == today { return .today }
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        return days <= 7 ? .nextSevenDays : .later
    }
}
