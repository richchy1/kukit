import SwiftUI
import SwiftData
import KukitCore

struct FocusView: View {
    @Environment(TimerController.self) private var timer
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context

    @Query(sort: \Course.name) private var allCourses: [Course]
    @Query(sort: [SortDescriptor(\TimerPreset.sortOrder), SortDescriptor(\TimerPreset.createdAt)])
    private var customPresets: [TimerPreset]

    @AppStorage(Prefs.keepScreenAwake) private var keepAwake = true

    @State private var presetSheet: PresetSheet?
    @State private var confirmDiscard = false

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

    private var courses: [Course] { allCourses.filter { !$0.isArchived } }
    private var state: TimerState { timer.state }
    private var selectedConfig: TimerConfig {
        PresetCatalog.resolve(id: timer.selectedPresetID, custom: customPresets)
    }
    private var activeCourse: Course? {
        let id = state.isActive ? state.context.courseID : timer.selectedCourseID
        return allCourses.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                TimerRingView(idleConfig: selectedConfig, courseColor: activeCourse?.color)
                    .frame(width: 280, height: 280)
                    .padding(.top, 8)

                if state.isActive {
                    activeSection
                } else {
                    startSection
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.screenBackground)
        .navigationTitle("Focus")
        .onAppear(perform: updateAwake)
        .onDisappear { ScreenAwake.set(false) }
        .onChange(of: state.status) { updateAwake() }
        .onChange(of: keepAwake) { updateAwake() }
        .sheet(item: $presetSheet) { sheet in
            switch sheet {
            case .new: PresetEditorView(preset: nil)
            case .edit(let preset): PresetEditorView(preset: preset)
            }
        }
        .confirmationDialog("Discard this session?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { timer.discard() }
        } message: {
            Text("The time you've focused so far won't be saved.")
        }
    }

    // MARK: Sections

    private var activeSection: some View {
        VStack(spacing: 20) {
            if let course = activeCourse {
                HStack(spacing: 10) {
                    CourseBadge(color: course.color, symbol: course.symbolName, size: 28)
                    Text("\(course.name) · \(state.config.name)")
                        .font(.subheadline.weight(.medium))
                }
            }
            TimerControls { confirmDiscard = true }
        }
    }

    private var startSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if courses.isEmpty {
                EmptyStateView(
                    systemImage: "books.vertical",
                    title: "Add a course first",
                    message: "Focus time is tracked per course, so you can see where your hours go.",
                    actionTitle: "Add a course"
                ) { router.section = .courses }
                .card()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Course").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    CoursePickerMenu(courses: courses, selectedID: timer.selectedCourseID) { timer.selectCourse($0) }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Technique").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
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
                }

                Button {
                    timer.start(config: selectedConfig)
                } label: {
                    Label(selectedConfig.kind == .stopwatch ? "Start stopwatch" : "Start focus", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(activeCourse?.color ?? Theme.accent)
                .disabled(timer.selectedCourseID == nil || activeCourse == nil)
            }
        }
    }

    // MARK: Actions

    private func deletePreset(_ config: TimerConfig) {
        guard let preset = customPresets.first(where: { $0.id.uuidString == config.id }) else { return }
        if timer.selectedPresetID == config.id { timer.selectPreset(.classic) }
        context.delete(preset)
        try? context.save()
    }

    private func updateAwake() {
        ScreenAwake.set(keepAwake && state.status == .running)
    }
}
