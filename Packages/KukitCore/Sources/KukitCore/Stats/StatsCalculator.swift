import Foundation

/// The minimum a stats calculation needs to know about a saved session.
public struct SessionSummary: Equatable, Sendable {
    public var startedAt: Date
    public var seconds: TimeInterval
    public var courseID: UUID?

    public init(startedAt: Date, seconds: TimeInterval, courseID: UUID? = nil) {
        self.startedAt = startedAt
        self.seconds = seconds
        self.courseID = courseID
    }
}

public struct DayTotal: Equatable, Sendable, Identifiable {
    public var day: Date          // start of day
    public var seconds: TimeInterval
    public var id: Date { day }
}

public struct CourseTotal: Equatable, Sendable, Identifiable {
    public var courseID: UUID?
    public var seconds: TimeInterval
    public var id: UUID { courseID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")! }
}

/// Pure statistics over saved sessions. Sessions are attributed to the day they started.
public struct StatsCalculator: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func total(_ sessions: [SessionSummary], on day: Date) -> TimeInterval {
        sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
            .reduce(0) { $0 + $1.seconds }
    }

    /// Totals for `days` consecutive days ending on (and including) `endDay`, oldest first.
    public func dailyTotals(_ sessions: [SessionSummary], endingOn endDay: Date, days: Int) -> [DayTotal] {
        guard days > 0 else { return [] }
        let end = calendar.startOfDay(for: endDay)
        var buckets: [Date: TimeInterval] = [:]
        for session in sessions {
            buckets[calendar.startOfDay(for: session.startedAt), default: 0] += session.seconds
        }
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            return DayTotal(day: day, seconds: buckets[day] ?? 0)
        }
    }

    /// Totals per course within `[start, end)`, biggest first.
    public func courseTotals(_ sessions: [SessionSummary], from start: Date, to end: Date) -> [CourseTotal] {
        var buckets: [UUID?: TimeInterval] = [:]
        for session in sessions where session.startedAt >= start && session.startedAt < end {
            buckets[session.courseID, default: 0] += session.seconds
        }
        return buckets.map { CourseTotal(courseID: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    /// Number of consecutive days, counting back from `asOf`, that met `goalSeconds`
    /// (at least one session when the goal is 0). Today not yet meeting the goal does
    /// not break the streak — it simply isn't counted yet.
    public func currentStreak(_ sessions: [SessionSummary], goalSeconds: TimeInterval, asOf now: Date) -> Int {
        var buckets: [Date: TimeInterval] = [:]
        for session in sessions {
            buckets[calendar.startOfDay(for: session.startedAt), default: 0] += session.seconds
        }
        let threshold = max(goalSeconds, 1)
        var day = calendar.startOfDay(for: now)
        if (buckets[day] ?? 0) < threshold {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while (buckets[day] ?? 0) >= threshold {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// The longest run of consecutive days that met `goalSeconds` (any session when the goal is 0).
    public func longestStreak(_ sessions: [SessionSummary], goalSeconds: TimeInterval) -> Int {
        var buckets: [Date: TimeInterval] = [:]
        for session in sessions {
            buckets[calendar.startOfDay(for: session.startedAt), default: 0] += session.seconds
        }
        let threshold = max(goalSeconds, 1)
        let days = buckets.filter { $0.value >= threshold }.keys.sorted()
        var longest = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day { run += 1 } else { run = 1 }
            longest = max(longest, run)
            previous = day
        }
        return longest
    }
}
