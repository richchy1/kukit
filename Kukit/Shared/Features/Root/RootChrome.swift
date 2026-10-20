import SwiftUI
import SwiftData
import KukitCore

/// Everything the window shell adds around the screens: the type and tint, refreshing the timer
/// and reminders when the app becomes active, toasts, the "session complete" card, and the
/// first-run welcome.
struct RootChrome: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(TimerController.self) private var timer
    @Environment(FocusMusicController.self) private var music

    func body(content: Content) -> some View {
        content
            .fontDesign(.rounded)
            .tint(Theme.accent)
            .foregroundStyle(Theme.ink)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    timer.refresh()
                    music.syncWithPlayer()
                    ReminderScheduler.shared.scheduleResync(context)
                }
            }
            .task { ReminderScheduler.shared.scheduleResync(context) }
            .modifier(CompletionHost())
            .modifier(ToastHost())
            .onboarding()
    }
}

extension View {
    func kukitRoot() -> some View { modifier(RootChrome()) }

    func miniPlayer() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
    }
}

// MARK: - Session complete

/// A card that slides up when a focus session ends: how long you cooked, a line from the chef,
/// and the next step (break, or another round).
struct CompletionHost: ViewModifier {
    @Environment(TimerController.self) private var timer

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let completion = timer.completion {
                SessionCompleteCard(completion: completion)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(completion.id)
            }
        }
        .animation(.snappy, value: timer.completion)
    }
}

struct SessionCompleteCard: View {
    let completion: SessionCompletion
    @Environment(TimerController.self) private var timer
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \StudySession.startedAt) private var sessions: [StudySession]
    @AppStorage(Prefs.dailyGoalMinutes) private var goalMinutes = 120

    private var course: Course? { courses.first { $0.id == completion.courseID } }
    private var goalSeconds: TimeInterval { TimeInterval(goalMinutes * 60) }

    private enum Highlight { case goal, record, first, plain }

    /// The best thing to celebrate right now.
    private var highlight: Highlight {
        let summaries = sessions.map(\.summary)
        let today = StatsCalculator().total(summaries, on: completion.endedAt)
        if goalSeconds > 0, today >= goalSeconds, today - completion.seconds < goalSeconds { return .goal }
        if Achievements.isRecordToday(summaries, now: completion.endedAt) { return .record }
        if sessions.count <= 1 { return .first }
        return .plain
    }

    private var headline: String {
        let seed = Int(completion.endedAt.timeIntervalSince1970 / 60)
        switch highlight {
        case .goal: return Chef.line(.goalComplete, seed: seed)
        case .record: return Chef.line(.recordDay, seed: seed)
        case .first: return Chef.line(.firstSession, seed: seed)
        case .plain: return Chef.line(.sessionComplete, seed: seed)
        }
    }

    var body: some View {
        let state = timer.state
        HStack(alignment: .top, spacing: 14) {
            ChefKukit(mood: highlight == .goal ? .goalDone : .celebrate, size: 78)
            VStack(alignment: .leading, spacing: 8) {
                Text(headline).font(.kukit(.headline, weight: .heavy))
                HStack(spacing: 8) {
                    Chip(text: DurationFormat.short(completion.seconds), systemImage: "checkmark.circle.fill", tint: Theme.basilText)
                    if let course { Chip(text: course.name, systemImage: course.symbolName, tint: course.color) }
                }
                Text("Logged in your cookbook.")
                    .font(.kukit(.caption, weight: .medium)).foregroundStyle(.secondary)
                actions(for: state)
            }
        }
        .padding(16)
        .frame(maxWidth: 460)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border) }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session complete. \(DurationFormat.short(completion.seconds)).")
    }

    @ViewBuilder
    private func actions(for state: TimerState) -> some View {
        HStack(spacing: 8) {
            switch state.status {
            case .awaitingStart where state.phase.isBreak:
                Button("Start break") { timer.dismissCompletion(); timer.startNext() }
                    .buttonStyle(.kukit(.primary, tint: Theme.basil))
                Button("Cook again") { timer.cookAgain() }
                    .buttonStyle(.kukit(.secondary))
            case .running where state.phase.isBreak:
                Button("Cook again") { timer.cookAgain() }
                    .buttonStyle(.kukit(.primary))
                Button("Enjoy the break") { timer.dismissCompletion() }
                    .buttonStyle(.kukit(.secondary))
            default:
                Button("Cook again") { timer.cookAgain() }
                    .buttonStyle(.kukit(.primary))
                Button("Done") { timer.dismissCompletion() }
                    .buttonStyle(.kukit(.secondary))
            }
        }
        .controlSize(.small)
        .padding(.top, 2)
    }
}
