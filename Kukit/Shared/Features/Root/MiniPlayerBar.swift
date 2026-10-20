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
            TimelineView(.animation(minimumInterval: 0.5, paused: state.status != .running)) { context in
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ProgressRing(
                            progress: state.progress(at: context.date),
                            tint: state.phase.isBreak ? Theme.breakGreen : (course?.color ?? Theme.accent),
                            lineWidth: 5
                        )
                        .frame(width: 34, height: 34)

                        VStack(alignment: .leading, spacing: 0) {
                            TimerDigits(text: text(state, at: context.date), size: 20)
                            Text(course?.name ?? state.subtitle)
                                .font(.caption)
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

                    actionButton(state)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 0.5)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ state: TimerState) -> some View {
        switch state.status {
        case .running:
            Button { timer.pause() } label: { Image(systemName: "pause.fill").frame(width: 32, height: 32) }
                .accessibilityLabel("Pause")
        case .paused:
            Button { timer.resume() } label: { Image(systemName: "play.fill").frame(width: 32, height: 32) }
                .accessibilityLabel("Resume")
        case .awaitingStart:
            Button { timer.startNext() } label: { Image(systemName: "play.fill").frame(width: 32, height: 32) }
                .accessibilityLabel("Start \(state.phase.title.lowercased())")
        case .idle:
            EmptyView()
        }
    }

    private func text(_ state: TimerState, at now: Date) -> String {
        if let remaining = state.remaining(at: now) { return DurationFormat.clock(remaining) }
        return DurationFormat.clock(state.elapsed(at: now).rounded(.down))
    }
}

extension View {
    func miniPlayer() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
    }

    /// Re-checks the timer and re-plans assignment reminders whenever the app becomes active
    /// (returning from the background, waking the Mac).
    func refreshTimerWhenActive(_ timer: TimerController, scenePhase: ScenePhase, context: ModelContext) -> some View {
        self
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    timer.refresh()
                    ReminderScheduler.shared.scheduleResync(context)
                }
            }
            .task { ReminderScheduler.shared.scheduleResync(context) }
            .onboarding()
    }
}
