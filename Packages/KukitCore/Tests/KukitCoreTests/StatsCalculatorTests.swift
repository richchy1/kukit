import Foundation
import Testing
@testable import KukitCore

@Suite("StatsCalculator")
struct StatsCalculatorTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    func session(_ day: Int, minutes: Double, hour: Int = 12, course: UUID? = nil) -> SessionSummary {
        SessionSummary(startedAt: date(day, hour: hour), seconds: minutes * 60, courseID: course)
    }

    @Test func totalForADay() {
        let stats = StatsCalculator(calendar: calendar)
        let sessions = [session(10, minutes: 25), session(10, minutes: 50, hour: 20), session(11, minutes: 30)]
        #expect(stats.total(sessions, on: date(10)) == 75 * 60)
        #expect(stats.total(sessions, on: date(12)) == 0)
    }

    @Test func dailyTotalsAreOldestFirstAndFillGaps() {
        let stats = StatsCalculator(calendar: calendar)
        let sessions = [session(8, minutes: 10), session(10, minutes: 20), session(10, minutes: 5)]
        let totals = stats.dailyTotals(sessions, endingOn: date(10, hour: 23), days: 4)
        #expect(totals.map(\.seconds) == [0, 600, 0, 1500])
        #expect(totals.first?.day == calendar.startOfDay(for: date(7)))
        #expect(totals.last?.day == calendar.startOfDay(for: date(10)))
    }

    @Test func courseTotalsAreSortedAndRangeLimited() {
        let stats = StatsCalculator(calendar: calendar)
        let a = UUID(), b = UUID()
        let sessions = [
            session(10, minutes: 30, course: a), session(11, minutes: 60, course: b),
            session(12, minutes: 15, course: a), session(20, minutes: 500, course: b),
            session(11, minutes: 5),
        ]
        let totals = stats.courseTotals(sessions, from: date(9), to: date(15))
        #expect(totals.map(\.courseID) == [b, a, nil])
        #expect(totals.map(\.seconds) == [3600, 2700, 300])
    }

    @Test func streakCountsConsecutiveDaysMeetingTheGoal() {
        let stats = StatsCalculator(calendar: calendar)
        let sessions = [session(8, minutes: 60), session(9, minutes: 70), session(10, minutes: 65)]
        #expect(stats.currentStreak(sessions, goalSeconds: 60 * 60, asOf: date(10, hour: 23)) == 3)
    }

    @Test func todayNotYetMetDoesNotBreakTheStreak() {
        let stats = StatsCalculator(calendar: calendar)
        let sessions = [session(8, minutes: 60), session(9, minutes: 70), session(10, minutes: 10)]
        #expect(stats.currentStreak(sessions, goalSeconds: 60 * 60, asOf: date(10, hour: 9)) == 2)
    }

    @Test func missedDayEndsTheStreak() {
        let stats = StatsCalculator(calendar: calendar)
        let sessions = [session(7, minutes: 90), session(9, minutes: 70), session(10, minutes: 65)]
        #expect(stats.currentStreak(sessions, goalSeconds: 60 * 60, asOf: date(10)) == 2)
        #expect(stats.currentStreak([], goalSeconds: 60 * 60, asOf: date(10)) == 0)
    }

    @Test func zeroGoalMeansAnySessionCounts() {
        let stats = StatsCalculator(calendar: calendar)
        let sessions = [session(9, minutes: 2), session(10, minutes: 1)]
        #expect(stats.currentStreak(sessions, goalSeconds: 0, asOf: date(10)) == 2)
    }
}
