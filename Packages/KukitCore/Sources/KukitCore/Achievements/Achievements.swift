import Foundation

public struct Achievement: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var isUnlocked: Bool
    /// 0...1 progress toward unlocking (1 when unlocked).
    public var progress: Double
}

/// Small milestones derived from the logged sessions. Nothing is stored: they are recomputed from
/// the session history, so they can never drift out of sync with the statistics.
public enum Achievements {
    public static func evaluate(
        _ sessions: [SessionSummary], goalSeconds: TimeInterval, now: Date, calendar: Calendar = .current
    ) -> [Achievement] {
        let stats = StatsCalculator(calendar: calendar)
        let total = sessions.reduce(0) { $0 + $1.seconds }
        let today = stats.total(sessions, on: now)
        let best = bestDay(sessions, calendar: calendar)
        let longest = stats.longestStreak(sessions, goalSeconds: goalSeconds)

        func ratio(_ value: Double, _ target: Double) -> Double { target > 0 ? min(1, value / target) : 0 }

        var list: [Achievement] = [
            Achievement(id: "first-session", title: "First dish served",
                        detail: "Complete your first focus session.",
                        isUnlocked: !sessions.isEmpty, progress: sessions.isEmpty ? 0 : 1),
        ]
        if goalSeconds > 0 {
            list.append(Achievement(
                id: "goal-today", title: "Today's meal is served",
                detail: "Reach your daily goal today.",
                isUnlocked: today >= goalSeconds, progress: ratio(today, goalSeconds)))
        }
        list.append(Achievement(
            id: "personal-best", title: "Personal best",
            detail: best.seconds > 0 ? "Your record day is \(DurationFormat.short(best.seconds))." : "Study for an hour in one day.",
            isUnlocked: best.seconds >= 3_600, progress: ratio(best.seconds, 3_600)))
        for days in [3, 7, 14, 30] {
            list.append(Achievement(
                id: "streak-\(days)", title: "\(days)-day streak",
                detail: "Hit your goal \(days) days in a row.",
                isUnlocked: longest >= days, progress: ratio(Double(longest), Double(days))))
        }
        for hours in [10, 50] {
            list.append(Achievement(
                id: "hours-\(hours)", title: "\(hours) hours in the kitchen",
                detail: "Log \(hours) hours of focus in total.",
                isUnlocked: total >= Double(hours) * 3_600, progress: ratio(total, Double(hours) * 3_600)))
        }
        return list
    }

    /// The day with the most focus time.
    public static func bestDay(_ sessions: [SessionSummary], calendar: Calendar = .current) -> (day: Date?, seconds: TimeInterval) {
        var buckets: [Date: TimeInterval] = [:]
        for s in sessions { buckets[calendar.startOfDay(for: s.startedAt), default: 0] += s.seconds }
        guard let best = buckets.max(by: { $0.value < $1.value }) else { return (nil, 0) }
        return (best.key, best.value)
    }

    /// True when today's total beats every earlier day (and is at least `minimum`).
    public static func isRecordToday(
        _ sessions: [SessionSummary], now: Date, minimum: TimeInterval = 1_800, calendar: Calendar = .current
    ) -> Bool {
        let today = calendar.startOfDay(for: now)
        let todayTotal = StatsCalculator(calendar: calendar).total(sessions, on: now)
        guard todayTotal >= minimum else { return false }
        let earlier = sessions.filter { calendar.startOfDay(for: $0.startedAt) < today }
        return todayTotal > bestDay(earlier, calendar: calendar).seconds
    }
}
