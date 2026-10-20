import AVFoundation
import Foundation
import Observation
import KukitCore
#if os(macOS)
import AppKit
#endif

/// Plays the focus track in step with the timer and exposes its state to the UI.
///
/// One instance owns exactly one player, so there can never be two copies of the track playing.
/// The timer tells it what to do (`apply(_:)`, driven by `FocusMusic.action`); the user can also
/// start, pause, mute and change the volume by hand. If the audio can't be loaded the timer is
/// unaffected: the controller records the error and the UI shows a small, non-blocking notice.
@MainActor
@Observable
final class FocusMusicController {
    enum State: Equatable {
        case stopped
        case playing
        case paused
        case failed(String)
    }

    private(set) var state: State = .stopped
    private(set) var isEnabled: Bool
    private(set) var volume: Double
    private(set) var isMuted: Bool
    private(set) var autoStart: Bool
    private(set) var resumeWithTimer: Bool

    /// Set by the timer controller so interruptions only resume music during focus time.
    @ObservationIgnored var isFocusRunning: () -> Bool = { false }
    /// Called with a user-facing message when playback fails (shown as a toast).
    @ObservationIgnored var onError: (String) -> Void = { _ in }

    @ObservationIgnored private let playback: MusicPlayback
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var resumeAfterTimerPause = false
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(playback: MusicPlayback = BundledMusicPlayback(), defaults: UserDefaults = .standard) {
        self.playback = playback
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Prefs.musicEnabled) as? Bool ?? true
        volume = defaults.object(forKey: Prefs.musicVolume) as? Double ?? 0.6
        isMuted = defaults.bool(forKey: Prefs.musicMuted)
        autoStart = defaults.object(forKey: Prefs.musicAutoStart) as? Bool ?? true
        resumeWithTimer = defaults.object(forKey: Prefs.musicResumeWithTimer) as? Bool ?? true
        observeSystemEvents()
    }

    // MARK: Read-only state

    var isPlaying: Bool { state == .playing }

    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    var currentTime: TimeInterval { playback.currentTime }
    var duration: TimeInterval { playback.duration }
    var policy: MusicPolicy {
        MusicPolicy(isEnabled: isEnabled, autoStart: autoStart, resumeWithTimer: resumeWithTimer)
    }

    // MARK: Timer-driven

    /// Carries out what `FocusMusic.action` decided for a timer transition.
    func apply(_ action: MusicAction) {
        switch action {
        case .none:
            break
        case .start:
            resumeAfterTimerPause = false
            resumeAfterInterruption = false
            beginPlayback(fromStart: true)
        case .pause:
            // Remember whether to resume: music the user already paused by hand stays paused.
            resumeAfterTimerPause = state == .playing
            pauseNow()
        case .resume:
            defer { resumeAfterTimerPause = false }
            if resumeAfterTimerPause, isEnabled { beginPlayback(fromStart: false) }
        case .stop:
            resumeAfterTimerPause = false
            resumeAfterInterruption = false
            stopNow()
        }
    }

    // MARK: User-driven

    /// The play/pause button. Outside a session this works as a preview.
    func toggle() {
        guard isEnabled else { return }
        if state == .playing {
            resumeAfterTimerPause = false
            pauseNow()
        } else {
            let startFresh: Bool
            switch state {
            case .stopped, .failed: startFresh = true
            case .playing, .paused: startFresh = false
            }
            beginPlayback(fromStart: startFresh)
        }
    }

    func setEnabled(_ value: Bool) {
        isEnabled = value
        defaults.set(value, forKey: Prefs.musicEnabled)
        if !value { stopNow() }
    }

    func setVolume(_ value: Double) {
        volume = min(max(value, 0), 1)
        defaults.set(volume, forKey: Prefs.musicVolume)
        applyVolume()
    }

    func setMuted(_ value: Bool) {
        isMuted = value
        defaults.set(value, forKey: Prefs.musicMuted)
        applyVolume()
    }

    func setAutoStart(_ value: Bool) {
        autoStart = value
        defaults.set(value, forKey: Prefs.musicAutoStart)
    }

    func setResumeWithTimer(_ value: Bool) {
        resumeWithTimer = value
        defaults.set(value, forKey: Prefs.musicResumeWithTimer)
    }

    /// Call when the app becomes active, or after the Mac wakes: the system may have stopped playback.
    func syncWithPlayer() {
        if state == .playing, !playback.isPlaying { state = .paused }
    }

    // MARK: Playback

    private func beginPlayback(fromStart: Bool) {
        guard isEnabled else { return }
        // Already playing and asked to continue: nothing to do (never a second playback).
        if state == .playing, !fromStart { return }
        do {
            try playback.prepare()
        } catch {
            fail(error)
            return
        }
        AudioSessionBridge.activate()
        playback.volume = effectiveVolume
        if fromStart, playback.currentTime > 0.1 { playback.stop() }
        if playback.play() {
            state = .playing
        } else {
            fail(MusicError.cannotPlay)
        }
    }

    private func pauseNow() {
        guard state == .playing else { return }
        playback.pause()
        state = .paused
    }

    private func stopNow() {
        if state != .stopped {
            playback.stop()
        }
        if case .failed = state {
            // keep the failure visible until the next successful start
        } else {
            state = .stopped
        }
        AudioSessionBridge.deactivate()
    }

    private func fail(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        state = .failed(message)
        onError(message)
    }

    private var effectiveVolume: Float { isMuted ? 0 : Float(volume) }
    private func applyVolume() { playback.volume = effectiveVolume }

    // MARK: System events

    private func observeSystemEvents() {
        let center = NotificationCenter.default
        #if os(iOS)
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            Task { @MainActor in self?.handleInterruption(type: type, shouldResume: options?.contains(.shouldResume) ?? false) }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            Task { @MainActor in
                // Headphones unplugged: pause rather than blast the speaker.
                if reason == .oldDeviceUnavailable { self?.pauseForSystem() }
            }
        })
        #else
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncWithPlayer() }
        })
        #endif
    }

    #if os(iOS)
    func handleInterruption(type: AVAudioSession.InterruptionType?, shouldResume: Bool) {
        switch type {
        case .began:
            // Remember only if music was actually playing; the system has already paused it.
            resumeAfterInterruption = state == .playing
            if state == .playing { state = .paused }
        case .ended:
            defer { resumeAfterInterruption = false }
            // Resume only when the system says it's appropriate AND a focus phase is still running.
            if shouldResume, resumeAfterInterruption, isFocusRunning(), isEnabled {
                beginPlayback(fromStart: false)
            }
        default:
            break
        }
    }

    private func pauseForSystem() {
        if state == .playing {
            playback.pause()
            state = .paused
        }
    }
    #endif
}

/// iPhone audio-session handling. On the Mac there is no audio session, so these do nothing.
@MainActor
enum AudioSessionBridge {
    static func activate() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
        #endif
    }

    static func deactivate() {
        #if os(iOS)
        // Let other apps' audio (a podcast, say) carry on once our music is done.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
