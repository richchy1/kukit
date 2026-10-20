import Foundation
import SwiftData
import Testing
import KukitCore
@testable import Kukit

/// A stand-in for the audio hardware: records what the controller asked it to do.
@MainActor
final class FakePlayback: MusicPlayback {
    enum Call: Equatable { case prepare, play, pause, stop }

    var calls: [Call] = []
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 3_000
    var volume: Float = 1
    var prepareError: MusicError?
    var playSucceeds = true

    func prepare() throws {
        calls.append(.prepare)
        if let prepareError { throw prepareError }
    }

    func play() -> Bool {
        calls.append(.play)
        guard playSucceeds else { return false }
        isPlaying = true
        return true
    }

    func pause() {
        calls.append(.pause)
        isPlaying = false
    }

    func stop() {
        calls.append(.stop)
        isPlaying = false
        currentTime = 0
    }

    var playCount: Int { calls.filter { $0 == .play }.count }
}

@MainActor
@Suite("Focus music")
struct MusicTests {
    let course: Course
    let context: ModelContext
    let defaults: UserDefaults

    init() throws {
        let container = try KukitSchema.makeContainer(inMemory: true)
        context = ModelContext(container)
        course = Course(name: "Calculus")
        context.insert(course)
        try context.save()
        let suite = "kukit.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        // The timer controller reads the app's own defaults for its options; make them predictable.
        Prefs.registerDefaults()
        UserDefaults.standard.removeObject(forKey: Prefs.timerState)
    }

    func makeTimer(_ fake: FakePlayback, music: FocusMusicController? = nil) -> (TimerController, FocusMusicController) {
        let controller = music ?? FocusMusicController(playback: fake, defaults: defaults)
        let timer = TimerController(modelContext: context, music: controller, schedulesNotifications: false)
        timer.selectCourse(course.id)
        return (timer, controller)
    }

    // MARK: Lifecycle

    @Test func startingAFocusSessionStartsTheMusic() {
        let fake = FakePlayback()
        let (timer, music) = makeTimer(fake)
        timer.start(config: .classic)
        #expect(music.state == .playing)
        #expect(fake.playCount == 1)
        #expect(fake.calls.first == .prepare)
    }

    @Test func pausingPausesAndResumingResumes() {
        let fake = FakePlayback()
        let (timer, music) = makeTimer(fake)
        timer.start(config: .classic)
        timer.pause()
        #expect(music.state == .paused)
        #expect(!fake.isPlaying)
        timer.resume()
        #expect(music.state == .playing)
        #expect(fake.isPlaying)
        #expect(fake.playCount == 2)
    }

    @Test func finishingAndCancellingBothStopTheMusic() {
        let fake = FakePlayback()
        let (timer, music) = makeTimer(fake)
        timer.start(config: .classic)
        timer.stop()                                  // Finish
        #expect(music.state == .stopped)
        #expect(!fake.isPlaying)
        #expect(fake.calls.last == .stop)

        timer.start(config: .classic)
        #expect(music.state == .playing)
        timer.discard()                               // Cancel
        #expect(music.state == .stopped)
        #expect(!fake.isPlaying)
    }

    @Test func cancellingWhilePausedStopsTheMusic() {
        let fake = FakePlayback()
        let (timer, music) = makeTimer(fake)
        timer.start(config: .classic)
        timer.pause()
        timer.discard()
        #expect(music.state == .stopped)
        #expect(!fake.isPlaying)
    }

    @Test func enteringABreakStopsTheMusicAndTheNextFocusRestartsItFromTheBeginning() {
        let fake = FakePlayback()
        let (timer, music) = makeTimer(fake)
        timer.start(config: .classic)
        fake.currentTime = 600
        timer.skip()                                  // focus → short break
        #expect(timer.state.phase == .shortBreak)
        #expect(music.state == .stopped)
        #expect(!fake.isPlaying)
        #expect(fake.currentTime == 0)

        timer.skip()                                  // break → next focus round
        #expect(timer.state.phase == .focus)
        #expect(music.state == .playing)
        #expect(fake.playCount == 2)
    }

    // MARK: Settings

    @Test func disabledMusicNeverStarts() {
        let fake = FakePlayback()
        let (timer, music) = makeTimer(fake)
        music.setEnabled(false)
        timer.start(config: .classic)
        #expect(music.state == .stopped)
        #expect(fake.playCount == 0)
        #expect(timer.state.status == .running)       // the timer is unaffected
    }

    @Test func turningMusicOffMidSessionStopsIt() {
        let fake = FakePlayback()
        let (timer, music) = makeTimer(fake)
        timer.start(config: .classic)
        music.setEnabled(false)
        #expect(music.state == .stopped)
        #expect(!fake.isPlaying)
        timer.pause()
        timer.resume()
        #expect(fake.playCount == 1)                  // still off
    }

    @Test func autoStartOffLeavesStartingToTheUser() {
        let fake = FakePlayback()
        let (timer, music) = makeTimer(fake)
        music.setAutoStart(false)
        timer.start(config: .classic)
        #expect(music.state == .stopped)
        music.toggle()                                // the user presses play
        #expect(music.state == .playing)
        timer.pause()
        #expect(music.state == .paused)
        timer.resume()
        #expect(music.state == .playing)              // resumed with the timer
    }

    @Test func resumeWithTimerCanBeDisabled() {
        let fake = FakePlayback()
        let (timer, music) = makeTimer(fake)
        music.setResumeWithTimer(false)
        timer.start(config: .classic)
        timer.pause()
        timer.resume()
        #expect(music.state == .paused)
        #expect(!fake.isPlaying)
    }

    @Test func musicThePausedByHandStaysPausedWhenTheTimerResumes() {
        let fake = FakePlayback()
        let (timer, music) = makeTimer(fake)
        timer.start(config: .classic)
        music.toggle()                                // user pauses the music, not the timer
        #expect(music.state == .paused)
        timer.pause()
        timer.resume()
        #expect(music.state == .paused)               // not restarted behind the user's back
        #expect(fake.playCount == 1)
    }

    @Test func settingsPersistAndReload() {
        let fake = FakePlayback()
        let music = FocusMusicController(playback: fake, defaults: defaults)
        music.setVolume(0.3); music.setMuted(true); music.setAutoStart(false)
        music.setResumeWithTimer(false); music.setEnabled(false)
        let reloaded = FocusMusicController(playback: FakePlayback(), defaults: defaults)
        #expect(abs(reloaded.volume - 0.3) < 0.0001)
        #expect(reloaded.isMuted && !reloaded.autoStart && !reloaded.resumeWithTimer && !reloaded.isEnabled)
    }

    @Test func volumeIsClampedAndMuteSilencesThePlayer() {
        let fake = FakePlayback()
        let (timer, music) = makeTimer(fake)
        timer.start(config: .classic)
        music.setVolume(5)
        #expect(music.volume == 1)
        music.setVolume(-1)
        #expect(music.volume == 0)
        music.setVolume(0.5)
        #expect(fake.volume == 0.5)
        music.setMuted(true)
        #expect(fake.volume == 0)
        music.setMuted(false)
        #expect(fake.volume == 0.5)
    }

    // MARK: Failure and safety

    @Test func aMissingAudioFileNeverBreaksTheTimer() {
        let fake = FakePlayback()
        fake.prepareError = .missingAsset
        let music = FocusMusicController(playback: fake, defaults: defaults)
        var reported: [String] = []
        music.onError = { reported.append($0) }
        let (timer, _) = makeTimer(fake, music: music)
        timer.start(config: .classic)
        #expect(timer.state.status == .running)       // the timer carries on
        #expect(music.errorMessage != nil)
        #expect(reported.count == 1)
        #expect(!fake.isPlaying)
        timer.pause(); timer.resume(); timer.stop()   // and the rest of the lifecycle still works
        #expect(timer.state.status == .idle)
    }

    @Test func aPlayerThatRefusesToPlayIsReportedNotCrashed() {
        let fake = FakePlayback()
        fake.playSucceeds = false
        let (timer, music) = makeTimer(fake)
        timer.start(config: .classic)
        #expect(music.errorMessage != nil)
        #expect(timer.state.status == .running)
    }

    @Test func thePlayerIsPreparedOnceAndNeverPlaysTwice() {
        let fake = FakePlayback()
        let (timer, music) = makeTimer(fake)
        timer.start(config: .classic)
        music.apply(.resume)                          // a stray extra resume
        music.apply(.resume)
        #expect(fake.calls.filter { $0 == .prepare }.count == 1)
        #expect(fake.playCount == 1)
        timer.pause()
        music.apply(.pause)                           // pausing twice is harmless
        #expect(fake.isPlaying == false)
    }

    @Test func aRestoredTimerNeverAutoStartsMusic() throws {
        // Simulate quitting mid-session: a running focus phase is saved.
        var engine = TimerEngine()
        engine.start(config: .deepWork, context: TimerContext(courseID: course.id), now: .now.addingTimeInterval(-300))
        UserDefaults.standard.set(try JSONEncoder().encode(engine.state), forKey: Prefs.timerState)
        defer { UserDefaults.standard.removeObject(forKey: Prefs.timerState) }

        let fake = FakePlayback()
        let music = FocusMusicController(playback: fake, defaults: defaults)
        let timer = TimerController(modelContext: context, music: music, schedulesNotifications: false)
        #expect(timer.state.status == .running)       // the session came back…
        #expect(fake.playCount == 0)                  // …but the music waits for the user
        #expect(music.state == .stopped)
        timer.stop()
    }

    @Test func syncingNoticesPlaybackTheSystemStopped() {
        let fake = FakePlayback()
        let (timer, music) = makeTimer(fake)
        timer.start(config: .classic)
        fake.isPlaying = false                        // e.g. the Mac slept
        music.syncWithPlayer()
        #expect(music.state == .paused)
    }

    /// The real asset: bundled with the app, loadable, and no longer than 50 minutes.
    @Test func theBundledTrackExistsLoadsAndIsAtMostFiftyMinutes() throws {
        let playback = BundledMusicPlayback()
        try playback.prepare()
        #expect(playback.duration > 60)
        #expect(playback.duration <= 3_000)
        #expect(!playback.isPlaying)
    }
}
