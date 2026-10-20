import SwiftUI
import SwiftData
import KukitCore

/// The timer, in two sizes: a `compact` card for the dashboard and the `immersive` Focus screen.
/// Both share the same state, controls, messages and music control.
struct FocusCard: View {
    enum Style { case compact, immersive }

    var style: Style = .compact

    @Environment(TimerController.self) private var timer
    @Environment(FocusMusicController.self) private var music
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context

    @Query(sort: \Course.name) private var allCourses: [Course]
    @Query private var assignments: [Assignment]
    @Query(sort: [SortDescriptor(\TimerPreset.sortOrder), SortDescriptor(\TimerPreset.createdAt)])
    private var customPresets: [TimerPreset]

    @State private var presetSheet: PresetSheet?
    @State private var confirmCancel = false

    private enum PresetSheet: Identifiable {
        case new
        case edit(TimerPreset)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let preset): preset.id.uuidString
            }
        }
    }

    private var immersive: Bool { style == .immersive }
    private var state: TimerState { timer.state }
    private var courses: [Course] { allCourses.filter { !$0.isArchived } }
    private var selectedConfig: TimerConfig {
        PresetCatalog.resolve(id: timer.selectedPresetID, custom: customPresets)
    }
    private var activeCourse: Course? {
        let id = state.isActive ? state.context.courseID : timer.selectedCourseID
        return allCourses.first { $0.id == id }
    }

    var body: some View {
        Group {
            if immersive {
                content
            } else {
                content.card(padding: 20, tone: state.isActive ? (state.phase.isBreak ? .success : .accent) : .plain)
            }
        }
        .sheet(item: $presetSheet) { sheet in
            switch sheet {
            case .new: PresetEditorView(preset: nil)
            case .edit(let preset): PresetEditorView(preset: preset)
            }
        }
        .confirmationDialog("Cancel this session?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel session", role: .destructive) { timer.discard() }
            Button("Keep cooking", role: .cancel) {}
        } message: {
            Text("The time you've focused so far won't be saved.")
        }
    }

    // MARK: Layout

    private var content: some View {
        VStack(spacing: immersive ? 22 : 16) {
            if immersive { chefHeader }
            TimerRingView(
                idleConfig: selectedConfig, courseColor: activeCourse?.color,
                digitSize: immersive ? 68 : 54, lineWidth: immersive ? 18 : 14
            )
            .frame(maxWidth: immersive ? 330 : 240)
            .accessibilityAddTraits(.updatesFrequently)

            if state.isActive { activeSection } else { idleSection }
        }
        .frame(maxWidth: .infinity)
    }

    private var chefHeader: some View {
        TimelineView(.periodic(from: .now, by: 2)) { context in
            VStack(spacing: 8) {
                ChefKukit(mood: state.chefMood(at: context.date), size: 104)
                Text(state.chefLine(at: context.date))
                    .font(.kukit(.subheadline, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.softBackground.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Idle

    @ViewBuilder
    private var idleSection: some View {
        if courses.isEmpty {
            EmptyStateView(
                mood: .idle, title: "Add a course first",
                message: Chef.line(.emptyCourses, seed: Chef.daySeed()),
                actionTitle: "Add a course"
            ) { router.section = .courses }
        } else {
            VStack(spacing: 12) {
                CoursePickerMenu(courses: courses, selectedID: timer.selectedCourseID) { timer.selectCourse($0) }

                if immersive {
                    PresetGrid(
                        configs: PresetCatalog.all(custom: customPresets),
                        selectedID: selectedConfig.id,
                        onSelect: { timer.selectPreset($0) },
                        onNew: { presetSheet = .new },
                        onEdit: { config in
                            if let preset = customPresets.first(where: { $0.id.uuidString == config.id }) {
                                presetSheet = .edit(preset)
                            }
                        },
                        onDelete: deletePreset
                    )
                } else {
                    TechniqueMenu(configs: PresetCatalog.all(custom: customPresets), selected: selectedConfig) {
                        timer.selectPreset($0)
                    }
                }

                if let task = assignment(timer.selectedAssignmentID) {
                    HStack {
                        Label("Cooking: \(task.title)", systemImage: "fork.knife")
                            .font(.kukit(.subheadline, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Button { timer.selectAssignment(nil) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear task")
                    }
                    .padding(12)
                    .background(Theme.softBackgroundFaint, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                }

                Button {
                    Haptics.play(.heavy)
                    timer.start(config: selectedConfig)
                } label: {
                    Label(selectedConfig.kind == .stopwatch ? "Start Stopwatch" : "Start Cooking", systemImage: "flame.fill")
                        .font(.kukit(.headline, weight: .heavy))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.kukit(.primary))
                .disabled(timer.selectedCourseID == nil || activeCourse == nil)
                .keyboardShortcut(.defaultAction)

                if immersive || music.isEnabled { MusicPill(showsVolume: immersive) }
            }
        }
    }

    // MARK: Active

    private var activeSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                if let course = activeCourse {
                    Chip(text: course.name, systemImage: course.symbolName, tint: course.color)
                }
                Chip(text: state.config.name, systemImage: state.isStopwatch ? "stopwatch.fill" : "timer", tint: Theme.ink.opacity(0.7))
            }
            if let task = assignment(state.context.assignmentID) {
                Label(task.title, systemImage: "fork.knife")
                    .font(.kukit(.footnote, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !immersive {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(state.chefLine(at: context.date))
                        .font(.kukit(.subheadline, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            TimerControls { confirmCancel = true }
            if immersive || music.isEnabled { MusicPill(showsVolume: immersive) }
        }
    }

    // MARK: Helpers

    private func assignment(_ id: UUID?) -> Assignment? {
        guard let id else { return nil }
        return assignments.first { $0.id == id }
    }

    private func deletePreset(_ config: TimerConfig) {
        guard let preset = customPresets.first(where: { $0.id.uuidString == config.id }) else { return }
        if timer.selectedPresetID == config.id { timer.selectPreset(.classic) }
        context.delete(preset)
        try? context.save()
    }
}
