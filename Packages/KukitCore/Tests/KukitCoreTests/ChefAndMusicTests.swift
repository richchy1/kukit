import Foundation
import Testing
@testable import KukitCore

@Suite("ChefMessages")
struct ChefMessagesTests {
    @Test func everyContextHasAtLeastTwoDistinctNonEmptyLines() {
        for context in ChefContext.allCases {
            let options = ChefMessages.lines[context] ?? []
            #expect(options.count >= 2, "\(context) needs more lines")
            #expect(Set(options).count == options.count, "\(context) has duplicates")
            #expect(options.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            #expect(!ChefMessages.plain(context).isEmpty)
        }
    }

    @Test func selectionIsDeterministicAndWrapsForAnySeed() {
        for context in ChefContext.allCases {
            let count = ChefMessages.lines[context]?.count ?? 1
            #expect(ChefMessages.message(context, seed: 7) == ChefMessages.message(context, seed: 7))
            #expect(ChefMessages.message(context, seed: 3) == ChefMessages.message(context, seed: 3 + count * 5))
            #expect(!ChefMessages.message(context, seed: -13).isEmpty)
            #expect(!ChefMessages.message(context, seed: Int.min + 1).isEmpty)
        }
    }

    @Test func differentSeedsReachDifferentLines() {
        let seen = Set((0..<20).map { ChefMessages.message(.working, seed: $0) })
        #expect(seen.count == ChefMessages.lines[.working]?.count)
    }

    @Test func dashboardGreetingFollowsTheHour() {
        #expect(ChefContext.dashboard(hour: 7) == .dashboardMorning)
        #expect(ChefContext.dashboard(hour: 13) == .dashboardAfternoon)
        #expect(ChefContext.dashboard(hour: 20) == .dashboardEvening)
        #expect(ChefContext.dashboard(hour: 2) == .dashboardLate)
        #expect(ChefContext.dashboard(hour: 23) == .dashboardLate)
        for hour in 0..<24 { #expect(ChefContext.allCases.contains(ChefContext.dashboard(hour: hour))) }
    }
}

@Suite("FocusMusic policy")
struct FocusMusicPolicyTests {
    let policy = MusicPolicy()
    let idle = TimerSnapshot.idle
    let focusRunning = TimerSnapshot(status: .running, phase: .focus)
    let focusPaused = TimerSnapshot(status: .paused, phase: .focus)
    let breakRunning = TimerSnapshot(status: .running, phase: .shortBreak)
    let longBreak = TimerSnapshot(status: .running, phase: .longBreak)
    let breakWaiting = TimerSnapshot(status: .awaitingStart, phase: .shortBreak)
    let focusWaiting = TimerSnapshot(status: .awaitingStart, phase: .focus)

    func action(_ a: TimerSnapshot, _ b: TimerSnapshot, _ p: MusicPolicy? = nil) -> MusicAction {
        FocusMusic.action(from: a, to: b, policy: p ?? policy)
    }

    @Test func startingAFocusSessionStartsTheMusic() {
        #expect(action(idle, focusRunning) == .start)
        #expect(action(focusWaiting, focusRunning) == .start)       // "start focus" after a break
    }

    @Test func pauseAndResumeFollowTheTimer() {
        #expect(action(focusRunning, focusPaused) == .pause)
        #expect(action(focusPaused, focusRunning) == .resume)
    }

    @Test func finishingOrCancellingStopsTheMusic() {
        #expect(action(focusRunning, idle) == .stop)               // finished early / cancelled
        #expect(action(focusPaused, idle) == .stop)                // cancelled while paused
    }

    @Test func enteringABreakStopsTheMusic() {
        #expect(action(focusRunning, breakRunning) == .stop)       // auto-started break
        #expect(action(focusRunning, longBreak) == .stop)
        #expect(action(focusRunning, breakWaiting) == .stop)       // break waiting for the user
        #expect(action(focusPaused, breakRunning) == .stop)        // skipped while paused
    }

    @Test func breaksAndIdleNeverStartMusic() {
        #expect(action(breakRunning, idle) == .none)
        #expect(action(breakRunning, focusWaiting) == .none)
        #expect(action(breakWaiting, breakRunning) == .none)
        #expect(action(idle, breakRunning) == .none)
        #expect(action(breakRunning, TimerSnapshot(status: .paused, phase: .shortBreak)) == .none)
    }

    @Test func aNewFocusSessionAfterABreakStartsTheMusicAgain() {
        #expect(action(breakRunning, focusRunning) == .start)
        #expect(action(longBreak, focusRunning) == .start)
        #expect(action(breakWaiting, focusRunning) == .start)      // break skipped
    }

    @Test func nothingChangesWhenNothingChanged() {
        for snapshot in [idle, focusRunning, focusPaused, breakRunning, breakWaiting, focusWaiting] {
            #expect(action(snapshot, snapshot) == .none)
        }
    }

    @Test func disabledMusicNeverStartsOrResumesButStillStops() {
        let off = MusicPolicy(isEnabled: false)
        #expect(action(idle, focusRunning, off) == .none)
        #expect(action(focusPaused, focusRunning, off) == .none)
        #expect(action(focusRunning, focusPaused, off) == .pause)  // harmless if something is playing
        #expect(action(focusRunning, idle, off) == .stop)
    }

    @Test func autoStartOffMeansTheUserStartsTheMusic() {
        let manual = MusicPolicy(autoStart: false)
        #expect(action(idle, focusRunning, manual) == .none)
        #expect(action(breakRunning, focusRunning, manual) == .none)
        #expect(action(focusPaused, focusRunning, manual) == .resume)
    }

    @Test func resumeWithTimerCanBeSwitchedOff() {
        let noResume = MusicPolicy(resumeWithTimer: false)
        #expect(action(focusPaused, focusRunning, noResume) == .none)
        #expect(action(idle, focusRunning, noResume) == .start)
    }

    @Test func aFullPomodoroCycleProducesTheExpectedActions() {
        // idle → focus → pause → resume → break → focus → idle
        let path = [idle, focusRunning, focusPaused, focusRunning, breakRunning, focusRunning, idle]
        let actions = zip(path, path.dropFirst()).map { action($0, $1) }
        #expect(actions == [.start, .pause, .resume, .stop, .start, .stop])
    }

    @Test func snapshotsComeFromTheTimerState() {
        var engine = TimerEngine()
        engine.start(config: .classic, context: TimerContext(), now: Date(timeIntervalSinceReferenceDate: 0))
        #expect(TimerSnapshot(engine.state) == focusRunning)
        engine.pause(now: Date(timeIntervalSinceReferenceDate: 60))
        #expect(TimerSnapshot(engine.state) == focusPaused)
    }
}

@Suite("Achievements")
struct AchievementsTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func day(_ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: d, hour: hour))!
    }

    func session(_ d: Int, minutes: Double) -> SessionSummary {
        SessionSummary(startedAt: day(d), seconds: minutes * 60)
    }

    func unlocked(_ list: [Achievement]) -> Set<String> { Set(list.filter(\.isUnlocked).map(\.id)) }

    @Test func nothingIsUnlockedWithoutSessions() {
        let list = Achievements.evaluate([], goalSeconds: 3_600, now: day(10), calendar: calendar)
        #expect(unlocked(list).isEmpty)
        #expect(list.allSatisfy { $0.progress == 0 })
    }

    @Test func firstSessionAndGoalToday() {
        let list = Achievements.evaluate([session(10, minutes: 25)], goalSeconds: 3_600, now: day(10), calendar: calendar)
        #expect(unlocked(list) == ["first-session"])
        let goal = list.first { $0.id == "goal-today" }
        #expect(goal.map { abs($0.progress - 25.0 / 60) < 0.001 } == true)

        let reached = Achievements.evaluate([session(10, minutes: 70)], goalSeconds: 3_600, now: day(10), calendar: calendar)
        #expect(unlocked(reached).isSuperset(of: ["first-session", "goal-today", "personal-best"]))
        // A goal reached yesterday doesn't count as today's.
        let yesterday = Achievements.evaluate([session(9, minutes: 70)], goalSeconds: 3_600, now: day(10), calendar: calendar)
        #expect(!unlocked(yesterday).contains("goal-today"))
    }

    @Test func noGoalMeansNoGoalAchievement() {
        let list = Achievements.evaluate([session(10, minutes: 25)], goalSeconds: 0, now: day(10), calendar: calendar)
        #expect(!list.contains { $0.id == "goal-today" })
    }

    @Test func streaksStayUnlockedAfterTheyEnd() {
        let sessions = (1...7).map { session($0, minutes: 60) }
        let list = Achievements.evaluate(sessions, goalSeconds: 3_600, now: day(20), calendar: calendar)
        #expect(unlocked(list).isSuperset(of: ["streak-3", "streak-7"]))
        #expect(!unlocked(list).contains("streak-14"))
        let fourteen = list.first { $0.id == "streak-14" }
        #expect(fourteen.map { abs($0.progress - 0.5) < 0.001 } == true)
    }

    @Test func totalHours() {
        let sessions = (1...10).map { session($0, minutes: 60) }
        let list = Achievements.evaluate(sessions, goalSeconds: 0, now: day(20), calendar: calendar)
        #expect(unlocked(list).contains("hours-10"))
        #expect(!unlocked(list).contains("hours-50"))
    }

    @Test func longestStreakCountsRunsNotTotals() {
        let stats = StatsCalculator(calendar: calendar)
        let sessions = [1, 2, 3, 5, 6, 10].map { session($0, minutes: 60) }
        #expect(stats.longestStreak(sessions, goalSeconds: 3_600) == 3)
        #expect(stats.longestStreak([], goalSeconds: 3_600) == 0)
        // Days under the goal break a run.
        let weak = [session(1, minutes: 60), session(2, minutes: 10), session(3, minutes: 60)]
        #expect(stats.longestStreak(weak, goalSeconds: 3_600) == 1)
    }

    @Test func recordDayNeedsToBeatEveryEarlierDay() {
        let earlier = [session(5, minutes: 90), session(6, minutes: 40)]
        #expect(Achievements.isRecordToday(earlier + [session(10, minutes: 120)], now: day(10), calendar: calendar))
        #expect(!Achievements.isRecordToday(earlier + [session(10, minutes: 80)], now: day(10), calendar: calendar))
        #expect(!Achievements.isRecordToday([session(10, minutes: 10)], now: day(10), calendar: calendar))   // too short to celebrate
        #expect(Achievements.bestDay(earlier, calendar: calendar).seconds == 90 * 60)
    }
}
