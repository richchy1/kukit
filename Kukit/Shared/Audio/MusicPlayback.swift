import AVFoundation
import Foundation

enum MusicError: LocalizedError, Equatable {
    case missingAsset
    case cannotLoad(String)
    case cannotPlay

    var errorDescription: String? {
        switch self {
        case .missingAsset: "The focus music file is missing from the app."
        case .cannotLoad(let reason): "The focus music couldn't be loaded (\(reason))."
        case .cannotPlay: "The focus music couldn't start playing."
        }
    }
}

/// What the music controller needs from an audio backend. The real one wraps `AVAudioPlayer`;
/// tests substitute a fake so the session/music logic never depends on real audio hardware.
@MainActor
protocol MusicPlayback: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var volume: Float { get set }
    /// Loads the audio. Safe to call repeatedly; only the first call does work.
    func prepare() throws
    @discardableResult func play() -> Bool
    func pause()
    /// Stops and rewinds to the start.
    func stop()
}

/// The bundled, trimmed focus track played with a single `AVAudioPlayer`.
@MainActor
final class BundledMusicPlayback: MusicPlayback {
    static let resourceName = "focus-music"
    static let resourceExtension = "m4a"

    private var player: AVAudioPlayer?
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    var isPlaying: Bool { player?.isPlaying ?? false }
    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var duration: TimeInterval { player?.duration ?? 0 }

    var volume: Float {
        get { player?.volume ?? 0 }
        set { player?.volume = newValue }
    }

    func prepare() throws {
        guard player == nil else { return }
        guard let url = bundle.url(forResource: Self.resourceName, withExtension: Self.resourceExtension) else {
            throw MusicError.missingAsset
        }
        do {
            let loaded = try AVAudioPlayer(contentsOf: url)
            loaded.numberOfLoops = -1      // the session, not the track, decides when the music ends
            loaded.prepareToPlay()
            player = loaded
        } catch {
            throw MusicError.cannotLoad(error.localizedDescription)
        }
    }

    @discardableResult
    func play() -> Bool { player?.play() ?? false }

    func pause() { player?.pause() }

    func stop() {
        player?.stop()
        player?.currentTime = 0
    }
}
