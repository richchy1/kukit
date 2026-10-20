import SwiftUI
import SwiftData
import KukitCore

/// A compact running-timer bar: sits above the tab bar on iPhone and at the bottom of the
/// sidebar on Mac. Visible only while a timer is active and Focus isn't already on screen.
struct MiniPlayerBar: View {
    @Environment(TimerController.self) private var timer
    @Environment(AppRouter.self) private var router
    @Query private var courses: [Course]

    var body: some View {
        if timer.state.isActive && router.section != .focus {
            let state = timer.state
            let course = courses.first { $0.id == state.context.courseID }
            let tint = state.phase.isBreak ? Theme.basil : (course?.color ?? Theme.accent)
            TimelineView(.periodic(from: state.tickAnchor, by: 1)) { context in
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ProgressRing(progress: state.progress(at: context.date), tint: tint, lineWidth: 5)
                            .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                TimerDigits(text: text(state, at: context.date), size: 21)
                                MusicBadge()
                            }
                            Text(course?.name ?? state.subtitle)
                                .font(.kukit(.caption, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { router.section = .focus }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("\(state.subtitle), \(text(state, at: context.date)). Open timer")

                    actionButton(state, tint: tint)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.cardBackground)
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                }
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border) }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ state: TimerState, tint: Color) -> some View {
        switch state.status {
        case .running: circleButton("pause.fill", label: "Pause", tint: tint) { timer.pause() }
        case .paused: circleButton("play.fill", label: "Resume", tint: tint) { timer.resume() }
        case .awaitingStart:
            circleButton("play.fill", label: "Start \(state.phase.title.lowercased())", tint: tint) { timer.startNext() }
        case .idle: EmptyView()
        }
    }

    private func circleButton(_ symbol: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func text(_ state: TimerState, at now: Date) -> String {
        if let remaining = state.remaining(at: now) { return DurationFormat.clock(remaining) }
        return DurationFormat.clock(state.elapsed(at: now).rounded(.down))
    }
}
