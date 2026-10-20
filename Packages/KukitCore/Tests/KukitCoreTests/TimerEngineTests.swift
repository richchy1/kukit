import Foundation
import Testing
@testable import KukitCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func at(_ minutes: Double, _ seconds: Double = 0) -> Date {
    t0.addingTimeInterval(minutes * 60 + seconds)
}

/// Dates around 2026 carry ~1e-7 s of floating-point noise, so compare durations with a tolerance.
private func near(_ value: TimeInterval?, _ expected: TimeInterval) -> Bool {
    guard let value else { return false }
    return abs(value - expected) < 0.001
}

private func recorded(_ events: [TimerEvent]) -> [FocusRecord] {
    events.compactMap { if case .focusRecorded(let r) = $0 { r } else { nil } }
}

@Suite("TimerEngine")
struct TimerEngineTests {
    let course = UUID()

    func started(_ config: TimerConfig = .classic, autoStart: Bool = true) -> TimerEngine {
        var engine = TimerEngine(options: TimerOptions(autoStartNext: autoStart, minimumSessionSeconds: 60))
        engine.start(config: config, context: TimerContext(courseID: course), now: t0)
        return engine
    }

    @Test func startBeginsFocusRoundOne() {
        let engine = started()
        #expect(engine.state.status == .running)
        #expect(engine.state.phase == .focus)
        #expect(engine.state.round == 1)
        #expect(engine.state.endDate == at(25))
        #expect(near(engine.state.remaining(at: at(10)), 15 * 60))
    }

    @Test func startIsIgnoredWhenNotIdle() {
        var engine = started()
        let events = engine.start(config: .deepWork, context: TimerContext(), now: at(1))
        #expect(events.isEmpty)
        #expect(engine.state.config == .classic)
    }

    @Test func pausedTimeIsNotCounted() {
        var engine = started()
        engine.pause(now: at(10))
        #expect(engine.state.status == .paused)
        // 30 minutes pass while paused
        engine.resume(now: at(40))
        #expect(near(engine.state.elapsed(at: at(45)), 15 * 60))
        // 10 min ran before the pause, so 15 min remain after resuming at minute 40
        #expect(engine.state.endDate == at(55))
    }

    @Test func needsAdvanceOnlyOnceThePhaseTimeIsUp() {
        var engine = started()
        #expect(!engine.needsAdvance(now: at(10)))
        #expect(!engine.needsAdvance(now: at(24, 59)))
        #expect(engine.needsAdvance(now: at(25)))
        #expect(engine.needsAdvance(now: at(60)))
        engine.pause(now: at(10))
        #expect(!engine.needsAdvance(now: at(500)))            // paused never ends by itself
        #expect(!TimerEngine().needsAdvance(now: at(0)))        // idle
        #expect(!started(.stopwatch).needsAdvance(now: at(9_999)))
    }

    @Test func advanceBeforeEndDoesNothing() {
        var engine = started()
        #expect(engine.advance(now: at(24, 59)).isEmpty)
        #expect(engine.state.phase == .focus)
    }

    @Test func focusEndsIntoShortBreakAndRecordsFullSession() {
        var engine = started()
        let events = engine.advance(now: at(25, 2))
        let records = recorded(events)
        #expect(records.count == 1)
        #expect(near(records[0].focusSeconds, 25 * 60))
        #expect(records[0].startedAt == t0)
        #expect(records[0].endedAt == at(25))
        #expect(records[0].context.courseID == course)
        #expect(records[0].presetName == "Classic")
        #expect(events.contains(.phaseEnded(.focus)))
        #expect(events.contains(.phaseStarted(.shortBreak)))
        #expect(engine.state.phase == .shortBreak)
        // the break counts from the exact end of focus, not from "now"
        #expect(engine.state.endDate == at(30))
    }

    @Test func autoStartOffWaitsForUser() {
        var engine = started(autoStart: false)
        engine.advance(now: at(25))
        #expect(engine.state.status == .awaitingStart)
        #expect(engine.state.phase == .shortBreak)
        #expect(near(engine.state.remaining(at: at(26)), 5 * 60))
        engine.startNext(now: at(26))
        #expect(engine.state.status == .running)
        #expect(engine.state.endDate == at(31))
    }

    @Test func fourthRoundLeadsToLongBreakThenResets() {
        var engine = started()
        var clock = 0.0
        for round in 1...3 {
            #expect(engine.state.round == round)
            clock += 25; engine.advance(now: at(clock))        // focus -> short break
            #expect(engine.state.phase == .shortBreak)
            clock += 5; engine.advance(now: at(clock))         // break -> next focus
        }
        #expect(engine.state.round == 4)
        clock += 25; engine.advance(now: at(clock))
        #expect(engine.state.phase == .longBreak)
        #expect(engine.state.endDate == at(clock + 15))
        clock += 15; engine.advance(now: at(clock))
        #expect(engine.state.phase == .focus)
        #expect(engine.state.round == 1)
    }

    @Test func deepWorkUsesThreeRounds() {
        var engine = started(.deepWork)
        engine.advance(now: at(50))   // -> short
        engine.advance(now: at(60))   // -> focus 2
        engine.advance(now: at(110))  // -> short
        engine.advance(now: at(120))  // -> focus 3
        engine.advance(now: at(170))  // -> long
        #expect(engine.state.phase == .longBreak)
        #expect(engine.state.endDate == at(190))
    }

    @Test func longAbsenceDoesNotChainPhasesOrLogExtraFocus() {
        var engine = started()
        // The app comes back 3 hours later.
        let events = engine.advance(now: at(180))
        #expect(recorded(events).count == 1)
        #expect(engine.state.status == .awaitingStart)
        #expect(engine.state.phase == .focus)          // stale break skipped
        #expect(engine.state.round == 2)
        // Waiting does not log anything further.
        #expect(engine.advance(now: at(200)).isEmpty)
    }

    @Test func absenceDuringBreakWaitsAtFocus() {
        var engine = started()
        engine.advance(now: at(25))                    // now in the break (ends 30)
        engine.advance(now: at(500))
        #expect(engine.state.status == .awaitingStart)
        #expect(engine.state.phase == .focus)
        #expect(engine.state.round == 2)
    }

    @Test func stopBelowMinimumIsDiscarded() {
        var engine = started()
        let events = engine.stop(now: at(0, 40))
        #expect(recorded(events).isEmpty)
        #expect(engine.state.status == .idle)
    }

    @Test func stopSavesPartialFocus() {
        var engine = started()
        let events = engine.stop(now: at(12, 30))
        let records = recorded(events)
        #expect(records.count == 1)
        #expect(near(records[0].focusSeconds, 12.5 * 60))
        #expect(records[0].endedAt == at(12, 30))
        #expect(engine.state.status == .idle)
    }

    @Test func stopWhilePausedUsesPausedElapsed() {
        var engine = started()
        engine.pause(now: at(10))
        let events = engine.stop(now: at(90))
        #expect(near(recorded(events).first?.focusSeconds, 10 * 60))
    }

    @Test func stoppingABreakSavesNothing() {
        var engine = started()
        engine.advance(now: at(25))
        let events = engine.stop(now: at(27))
        #expect(recorded(events).isEmpty)
        #expect(engine.state.status == .idle)
    }

    @Test func skipFocusSavesPartialAndStartsBreakNow() {
        var engine = started()
        let events = engine.skip(now: at(10))
        #expect(near(recorded(events).first?.focusSeconds, 10 * 60))
        #expect(engine.state.phase == .shortBreak)
        #expect(engine.state.endDate == at(15))
    }

    @Test func skipBreakStartsNextFocus() {
        var engine = started()
        engine.advance(now: at(25))
        let events = engine.skip(now: at(26))
        #expect(recorded(events).isEmpty)
        #expect(engine.state.phase == .focus)
        #expect(engine.state.round == 2)
        #expect(engine.state.endDate == at(51))
    }

    @Test func skippingAWaitingBreakGoesToFocus() {
        var engine = started(autoStart: false)
        engine.advance(now: at(25))
        engine.skip(now: at(26))
        #expect(engine.state.status == .awaitingStart)
        #expect(engine.state.phase == .focus)
        #expect(engine.state.round == 2)
    }

    @Test func discardSavesNothing() {
        var engine = started()
        engine.discard()
        #expect(engine.state == .idle)
    }

    // MARK: Stopwatch

    @Test func stopwatchCountsUpAndSavesOnStop() {
        var engine = started(.stopwatch)
        #expect(engine.state.phaseDuration == nil)
        #expect(engine.state.endDate == nil)
        #expect(engine.state.remaining(at: at(5)) == nil)
        #expect(engine.advance(now: at(600)).isEmpty)       // never ends by itself
        engine.pause(now: at(30))
        engine.resume(now: at(60))
        let events = engine.stop(now: at(90))
        let record = recorded(events).first
        #expect(near(record?.focusSeconds, 60 * 60))             // 30 + 30 running minutes
        #expect(record?.kind == .stopwatch)
        #expect(engine.state.status == .idle)
    }

    @Test func stopwatchCannotBeSkipped() {
        var engine = started(.stopwatch)
        #expect(engine.skip(now: at(5)).isEmpty)
        #expect(engine.state.status == .running)
    }

    @Test func stopwatchProgressLoopsEveryHour() {
        let engine = started(.stopwatch)
        #expect(engine.state.progress(at: at(30)) == 0.5)
        #expect(engine.state.progress(at: at(90)) == 0.5)
    }

    // MARK: Persistence & alerts

    @Test func stateSurvivesEncodeDecodeAndRestoresAfterTheEndDate() throws {
        var engine = started()
        engine.pause(now: at(5))
        engine.resume(now: at(6))
        let data = try JSONEncoder().encode(engine.state)
        let decoded = try JSONDecoder().decode(TimerState.self, from: data)
        #expect(decoded == engine.state)

        var restored = TimerEngine(state: decoded, options: engine.options)
        let events = restored.advance(now: at(26))      // phase ended at 26 (5 min ran, resumed at 6 -> 26)
        #expect(recorded(events).count == 1)
        #expect(restored.state.phase == .shortBreak)
    }

    @Test func pendingAlertsCoverCurrentAndNextPhase() {
        let engine = started()
        let alerts = engine.pendingAlerts(now: at(1))
        #expect(alerts.count == 2)
        #expect(alerts[0] == PhaseAlert(date: at(25), endingPhase: .focus, upcomingPhase: .shortBreak))
        #expect(alerts[1] == PhaseAlert(date: at(30), endingPhase: .shortBreak, upcomingPhase: .focus))
    }

    @Test func pendingAlertsWithoutAutoStartIsJustTheCurrentPhase() {
        let engine = started(autoStart: false)
        #expect(engine.pendingAlerts(now: at(1)).count == 1)
    }

    @Test func noAlertsWhenPausedIdleOrStopwatch() {
        var engine = started()
        engine.pause(now: at(1))
        #expect(engine.pendingAlerts(now: at(2)).isEmpty)
        #expect(TimerEngine().pendingAlerts(now: at(0)).isEmpty)
        #expect(started(.stopwatch).pendingAlerts(now: at(1)).isEmpty)
    }

    @Test func customConfigIsClampedToLimits() {
        let wild = TimerConfig(name: "Wild", focusMinutes: 999, shortBreakMinutes: 0,
                               longBreakMinutes: 500, roundsBeforeLongBreak: 1)
        var engine = TimerEngine()
        engine.start(config: wild, context: TimerContext(), now: t0)
        #expect(engine.state.config.focusMinutes == 240)
        #expect(engine.state.config.shortBreakMinutes == 1)
        #expect(engine.state.config.longBreakMinutes == 120)
        #expect(engine.state.config.roundsBeforeLongBreak == 2)
    }
}

@Suite("DurationFormat")
struct DurationFormatTests {
    @Test func clock() {
        #expect(DurationFormat.clock(0) == "00:00")
        #expect(DurationFormat.clock(25 * 60) == "25:00")
        #expect(DurationFormat.clock(18 * 60 + 41.2) == "18:42")   // rounds up like a countdown
        #expect(DurationFormat.clock(3600 + 5 * 60 + 9) == "1:05:09")
    }

    @Test func short() {
        #expect(DurationFormat.short(45) == "45s")
        #expect(DurationFormat.short(25 * 60) == "25m")
        #expect(DurationFormat.short(95 * 60) == "1h 35m")
        #expect(DurationFormat.short(2 * 3600) == "2h")
    }
}
