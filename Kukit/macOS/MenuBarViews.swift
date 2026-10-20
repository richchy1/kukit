import SwiftUI
import SwiftData
import AppKit
import KukitCore

/// The text and icon shown in the menu bar itself.
struct MenuBarLabel: View {
    @Environment(TimerController.self) private var timer
    @AppStorage(Prefs.menuBarCountdown) private var showCountdown = true

    var body: some View {
        let state = timer.state
        HStack(spacing: 4) {
            Image(systemName: state.isActive && state.phase.isBreak ? "cup.and.saucer.fill" : "flame.fill")
            if state.isActive && showCountdown {
                Text(timer.clockText).monospacedDigit()
            }
        }
    }
}

/// The popover that opens from the menu bar icon.
struct MenuBarTimerView: View {
    @Environment(TimerController.self) private var timer
    @Environment(FocusMusicController.self) private var music
    @Environment(AppRouter.self) private var router
    @Environment(\.openWindow) private var openWindow

    @Query(sort: \Course.name) private var allCourses: [Course]
    @Query(sort: [SortDescriptor(\TimerPreset.sortOrder), SortDescriptor(\TimerPreset.createdAt)])
    private var customPresets: [TimerPreset]
    @State private var confirmCancel = false

    private var courses: [Course] { allCourses.filter { !$0.isArchived } }
    private var state: TimerState { timer.state }
    private var configs: [TimerConfig] { PresetCatalog.all(custom: customPresets) }
    private var selectedConfig: TimerConfig {
        PresetCatalog.resolve(id: timer.selectedPresetID, custom: customPresets)
    }
    private var activeCourse: Course? {
        let id = state.isActive ? state.context.courseID : timer.selectedCourseID
        return allCourses.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 2)) { context in
                    ChefKukit(mood: state.chefMood(at: context.date), size: 40)
                }
                Text("Kukit").font(.kukit(.title3, weight: .heavy))
                Spacer()
            }

            TimerRingView(idleConfig: selectedConfig, courseColor: activeCourse?.color, digitSize: 40, lineWidth: 11)
                .frame(width: 180, height: 180)

            if state.isActive {
                if let course = activeCourse {
                    Chip(text: course.name, systemImage: course.symbolName, tint: course.color)
                }
                TimerControls { confirmCancel = true }
                if music.isEnabled { MusicPill() }
            } else if courses.isEmpty {
                Text("Add a course in Kukit to start cooking.")
                    .font(.kukit(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                CoursePickerMenu(courses: courses, selectedID: timer.selectedCourseID) { timer.selectCourse($0) }
                TechniqueMenu(configs: configs, selected: selectedConfig) { timer.selectPreset($0) }

                Button {
                    timer.start(config: selectedConfig)
                } label: {
                    Label(selectedConfig.kind == .stopwatch ? "Start Stopwatch" : "Start Cooking", systemImage: "flame.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.kukit(.primary))
                .disabled(activeCourse == nil)

                if music.isEnabled { MusicPill() }
            }

            Divider().opacity(0.6)

            HStack {
                Button("Open Kukit") {
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.kukit(.ghost))
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.screenBackground)
        .fontDesign(.rounded)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .confirmationDialog("Cancel this session?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel session", role: .destructive) { timer.discard() }
            Button("Keep cooking", role: .cancel) {}
        } message: {
            Text("The time you've focused so far won't be saved.")
        }
    }
}
