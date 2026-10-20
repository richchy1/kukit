import SwiftUI
import KukitCore

/// The compact music control on the timer: play/pause, mute and (optionally) volume.
/// It shows clearly when music is off or unavailable, and never blocks the timer.
struct MusicPill: View {
    @Environment(FocusMusicController.self) private var music
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var showsVolume = false

    var body: some View {
        HStack(spacing: 10) {
            if music.isEnabled {
                Button {
                    Haptics.play(.tap)
                    music.toggle()
                } label: {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(music.isPlaying ? "Pause music" : "Play music")
            } else {
                Image(systemName: "music.note.slash")
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Theme.softBackground.opacity(0.6), in: Circle())
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("Focus music").font(.kukit(.subheadline, weight: .bold))
                    if music.isPlaying {
                        Image(systemName: "waveform")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                            .accessibilityHidden(true)
                    }
                }
                statusText
                    .font(.kukit(.caption, weight: .medium))
                    .foregroundStyle(music.errorMessage == nil ? Color.secondary : Theme.accentText)
            }

            Spacer(minLength: 0)

            if music.isEnabled {
                if showsVolume {
                    Slider(value: Binding(get: { music.volume }, set: { music.setVolume($0) }), in: 0...1)
                        .frame(maxWidth: 120)
                        .tint(Theme.accent)
                        .disabled(music.isMuted)
                        .accessibilityLabel("Music volume")
                }
                Button {
                    music.setMuted(!music.isMuted)
                } label: {
                    Image(systemName: music.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(music.isMuted ? Theme.accentText : Color.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(music.isMuted ? "Unmute music" : "Mute music")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.softBackgroundFaint, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border) }
    }

    @ViewBuilder
    private var statusText: some View {
        if !music.isEnabled {
            Text("Off in Settings")
        } else if let message = music.errorMessage {
            Text("Unavailable · timer works as usual").help(message)
        } else if music.isPlaying {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text("Playing · \(DurationFormat.clock(music.currentTime))")
            }
        } else if music.state == .paused {
            Text("Paused · \(DurationFormat.clock(music.currentTime))")
        } else {
            Text("Plays when you start cooking")
        }
    }
}

/// A one-line "music is on" indicator for the mini player and menu bar.
struct MusicBadge: View {
    @Environment(FocusMusicController.self) private var music
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if music.isPlaying {
            Image(systemName: "music.note")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.bounce.up, options: .repeating.speed(0.4), isActive: !reduceMotion)
                .accessibilityLabel("Music playing")
        }
    }
}

/// Settings ▸ Focus music.
struct MusicSettingsSection: View {
    @Environment(FocusMusicController.self) private var music

    var body: some View {
        KSection {
            Toggle("Play music while I focus", isOn: Binding(get: { music.isEnabled }, set: { music.setEnabled($0) }))
            if music.isEnabled {
                Toggle("Start with every focus session", isOn: Binding(get: { music.autoStart }, set: { music.setAutoStart($0) }))
                Toggle("Resume when a paused session resumes", isOn: Binding(
                    get: { music.resumeWithTimer }, set: { music.setResumeWithTimer($0) }
                ))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text("\(Int((music.volume * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { music.volume }, set: { music.setVolume($0) }), in: 0...1)
                            .tint(Theme.accent)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                    Toggle("Mute", isOn: Binding(get: { music.isMuted }, set: { music.setMuted($0) }))
                }
                MusicPill()
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
        } header: {
            Text("Focus music")
        } footer: {
            Text("Music plays during focus time only. It pauses and resumes with the timer and stops when a session ends, is cancelled, or turns into a break. The track is a 50-minute loop kept on this device.")
        }
    }
}
