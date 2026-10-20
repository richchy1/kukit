import Foundation
import Testing
@testable import KukitCore

@Suite("ReminderPlanner & DueBucket")
struct ReminderPlannerTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    func task(due: Date, hasTime: Bool = true, offsets: [Int] = [1440, 120], exam: Bool = false) -> ReminderTask {
        ReminderTask(id: UUID(), title: "Problem set 5", courseName: "Calculus", isExam: exam,
                     due: due, hasTime: hasTime, offsets: offsets)
    }

    @Test func timedTaskGetsOneReminderPerFutureOffset() {
        let planner = ReminderPlanner(calendar: calendar)
        let t = task(due: date(20, 23, 59))
        let planned = planner.plan([t], now: date(10))
        #expect(planned.count == 2)
        #expect(planned[0].fireDate == date(19, 23, 59))
        #expect(planned[1].fireDate == date(20, 21, 59))
        #expect(planned[0].title == "Calculus: Problem set 5")
        #expect(planned[0].body == "Due tomorrow")
        #expect(planned[1].body == "Due in 2 hours")
    }

    @Test func offsetsInThePastAreSkipped() {
        let planner = ReminderPlanner(calendar: calendar)
        let t = task(due: date(20, 23, 59))
        // 1 day before has passed; 2 hours before has not
        let planned = planner.plan([t], now: date(20, 10))
        #expect(planned.map(\.body) == ["Due in 2 hours"])
        #expect(planner.plan([t], now: date(21)).isEmpty)
    }

    @Test func dateOnlyTasksFireInTheMorning() {
        let planner = ReminderPlanner(calendar: calendar, allDayHour: 9)
        let t = task(due: date(20, 0), hasTime: false)
        let planned = planner.plan([t], now: date(10))
        #expect(planned.count == 2)
        #expect(planned[0].fireDate == date(19, 9))      // 1 day before, 9:00
        #expect(planned[1].fireDate == date(20, 9))      // 2 h offset -> 0 days -> morning of
        #expect(planned[0].body == "Due tomorrow")
        #expect(planned[1].body == "Due today")
    }

    @Test func examsUseExamWording() {
        let planner = ReminderPlanner(calendar: calendar)
        let t = task(due: date(25, 14), offsets: ReminderPlanner.defaultOffsets(isExam: true), exam: true)
        let planned = planner.plan([t], now: date(10))
        #expect(planned.map(\.body) == ["Exam in 3 days", "Exam tomorrow", "Exam in 2 hours"])
    }

    @Test func defaultOffsets() {
        #expect(ReminderPlanner.defaultOffsets(isExam: false) == [1440, 120])
        #expect(ReminderPlanner.defaultOffsets(isExam: true) == [4320, 1440, 120])
    }

    @Test func duplicateFireTimesCollapse() {
        let planner = ReminderPlanner(calendar: calendar)
        // For a date-only task, 60 and 120 minutes both mean "morning of".
        let t = task(due: date(20, 0), hasTime: false, offsets: [60, 120])
        #expect(planner.plan([t], now: date(10)).count == 1)
    }

    @Test func plansOnlyTheSoonestRemindersWithinTheLimit() {
        let planner = ReminderPlanner(calendar: calendar, limit: 5)
        let tasks = (11...20).map { task(due: date($0, 23, 0), offsets: [120]) }
        let planned = planner.plan(tasks, now: date(10))
        #expect(planned.count == 5)
        #expect(planned.last?.fireDate == date(15, 21, 0))
        #expect(planned.map(\.fireDate) == planned.map(\.fireDate).sorted())
    }

    @Test func identifiersAreStablePerTaskAndOffset() {
        let planner = ReminderPlanner(calendar: calendar)
        let t = task(due: date(20, 23, 59))
        let a = planner.plan([t], now: date(10))
        let b = planner.plan([t], now: date(11))
        #expect(a.map(\.id) == b.map(\.id))
        #expect(a[0].id.hasPrefix(ReminderPlanner.identifierPrefix))
    }

    @Test func phraseWording() {
        #expect(ReminderPlanner.phrase(offsetMinutes: 0, hasTime: true, isExam: false) == "Due now")
        #expect(ReminderPlanner.phrase(offsetMinutes: 30, hasTime: true, isExam: false) == "Due in 30 min")
        #expect(ReminderPlanner.phrase(offsetMinutes: 60, hasTime: true, isExam: false) == "Due in 1 hour")
        #expect(ReminderPlanner.phrase(offsetMinutes: 2880, hasTime: true, isExam: false) == "Due in 2 days")
        #expect(ReminderPlanner.phrase(offsetMinutes: 0, hasTime: false, isExam: true) == "Exam today")
    }

    // MARK: DueBucket

    @Test func bucketsByDay() {
        let now = date(10, 15)
        func b(_ due: Date?, time: Bool = false) -> DueBucket {
            DueBucket.bucket(due: due, hasTime: time, now: now, calendar: calendar)
        }
        #expect(b(nil) == .noDate)
        #expect(b(date(9, 0)) == .overdue)
        #expect(b(date(10, 0)) == .today)
        #expect(b(date(11, 0)) == .nextSevenDays)
        #expect(b(date(17, 0)) == .nextSevenDays)
        #expect(b(date(18, 0)) == .later)
    }

    @Test func timedTaskEarlierTodayIsOverdue() {
        let now = date(10, 15)
        #expect(DueBucket.bucket(due: date(10, 9), hasTime: true, now: now, calendar: calendar) == .overdue)
        #expect(DueBucket.bucket(due: date(10, 23), hasTime: true, now: now, calendar: calendar) == .today)
        // A date-only task due today is not overdue until the day ends.
        #expect(DueBucket.bucket(due: date(10, 0), hasTime: false, now: now, calendar: calendar) == .today)
    }
}
