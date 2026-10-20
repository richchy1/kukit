import SwiftUI
import SwiftData
import AppKit
import KukitCore

/// The text and icon shown in the menu bar itself.
struct MenuBarLabel: View {
    @Environment(TimerController.self) private var timer
    @AppStorage(Prefs.menuBarCountdown) private var showCountdown = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = timer.state
            HStack(spacing: 4) {
                Image(systemName: state.isActive && state.phase.isBreak ? "cup.and.saucer.fill" : "timer")
                if state.isActive && showCountdown {
                    Text(text(state, at: context.date)).monospacedDigit()
                }
            }
        }
    }

    private func text(_ state: TimerState, at now: Date) -> String {
        if let remaining = state.remaining(at: now) { return DurationFormat.clock(remaining) }
        return DurationFormat.clock(state.elapsed(at: now).rounded(.down))
    }
}

/// The popover that opens from the menu bar icon.
struct MenuBarTimerView: View {
    @Environment(TimerController.self) private var timer
    @Environment(AppRouter.self) private var router
    @Environment(\.openWindow) private var openWindow

    @Query(sort: \Course.name) private var allCourses: [Course]
    @Query(sort: [SortDescriptor(\TimerPreset.sortOrder), SortDescriptor(\TimerPreset.createdAt)])
    private var customPresets: [TimerPreset]

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
            TimerRingView(idleConfig: selectedConfig, courseColor: activeCourse?.color, digitSize: 38, lineWidth: 10)
                .frame(width: 170, height: 170)

            if state.isActive {
                if let course = activeCourse {
                    Text(course.name).font(.subheadline.weight(.medium))
                }
                TimerControls { timer.discard() }
            } else if courses.isEmpty {
                Text("Add a course in Kukit to start tracking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                CoursePickerMenu(courses: courses, selectedID: timer.selectedCourseID) { timer.selectCourse($0) }

                Menu {
                    ForEach(configs) { config in
                        Button { timer.selectPreset(config) } label: {
                            if config.id == selectedConfig.id {
                                Label("\(config.name) · \(config.summary)", systemImage: "checkmark")
                            } else {
                                Text("\(config.name) · \(config.summary)")
                            }
                        }
                    }
                } label: {
                    Label("\(selectedConfig.name) · \(selectedConfig.summary)", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button {
                    timer.start(config: selectedConfig)
                } label: {
                    Label(selectedConfig.kind == .stopwatch ? "Start stopwatch" : "Start focus", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(activeCourse?.color ?? Theme.accent)
                .disabled(activeCourse == nil)
            }

            Divider()

            HStack {
                Button("Open Kukit") {
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 300)
    }
}
