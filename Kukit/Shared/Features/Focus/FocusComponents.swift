import SwiftUI
import SwiftData
import KukitCore

enum PresetCatalog {
    static func all(custom: [TimerPreset]) -> [TimerConfig] {
        TimerConfig.builtIns + custom.map(\.config)
    }

    static func resolve(id: String, custom: [TimerPreset]) -> TimerConfig {
        all(custom: custom).first { $0.id == id } ?? .classic
    }
}

extension TimerPhase {
    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }
}

extension TimerState {
    /// The line under the big digits.
    var subtitle: String {
        switch status {
        case .idle:
            return "Ready"
        case .paused:
            return "Paused"
        case .awaitingStart:
            return "Up next: \(phase.title.lowercased())"
        case .running:
            if isStopwatch { return "Stopwatch" }
            if phase == .focus { return "Focus · Round \(round) of \(config.roundsBeforeLongBreak)" }
            return phase.title
        }
    }

    var tint: Color {
        phase.isBreak ? Theme.breakGreen : Theme.accent
    }
}

// MARK: Ring

/// The big ring + digits. Reads the timer's dates and redraws twice a second while running.
struct TimerRingView: View {
    @Environment(TimerController.self) private var timer
    var idleConfig: TimerConfig
    var courseColor: Color?
    var digitSize: CGFloat = 60
    var lineWidth: CGFloat = 14
    var showsSubtitle = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: timer.state.status != .running)) { context in
            let state = timer.state
            let tint = state.isActive && state.phase.isBreak ? Theme.breakGreen : (courseColor ?? Theme.accent)
            ProgressRing(progress: progress(state, now: context.date), tint: tint, lineWidth: lineWidth) {
                VStack(spacing: 6) {
                    TimerDigits(text: digits(state, now: context.date), size: digitSize)
                    if showsSubtitle {
                        Text(state.isActive ? state.subtitle : "Ready")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, lineWidth * 1.5)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.isActive ? state.subtitle : "Timer ready")
            .accessibilityValue(spoken(state, now: context.date))
        }
    }

    private func digits(_ state: TimerState, now: Date) -> String {
        guard state.isActive else {
            return idleConfig.kind == .stopwatch ? "00:00" : DurationFormat.clock(TimeInterval(idleConfig.focusMinutes * 60))
        }
        if let remaining = state.remaining(at: now) { return DurationFormat.clock(remaining) }
        return DurationFormat.clock(state.elapsed(at: now).rounded(.down))   // stopwatch counts up
    }

    private func progress(_ state: TimerState, now: Date) -> Double {
        state.isActive ? state.progress(at: now) : 0
    }

    private func spoken(_ state: TimerState, now: Date) -> String {
        guard state.isActive else { return "" }
        if let remaining = state.remaining(at: now) {
            let minutes = Int((remaining / 60).rounded(.up))
            return "\(minutes) minute\(minutes == 1 ? "" : "s") remaining"
        }
        let minutes = Int(state.elapsed(at: now) / 60)
        return "\(minutes) minute\(minutes == 1 ? "" : "s") elapsed"
    }
}

// MARK: Pickers

struct CoursePickerMenu: View {
    var courses: [Course]
    var selectedID: UUID?
    var onSelect: (UUID) -> Void

    private var selected: Course? { courses.first { $0.id == selectedID } }

    var body: some View {
        Menu {
            ForEach(courses) { course in
                Button {
                    onSelect(course.id)
                } label: {
                    if course.id == selectedID {
                        Label(course.name, systemImage: "checkmark")
                    } else {
                        Text(course.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                if let selected {
                    CourseBadge(color: selected.color, symbol: selected.symbolName, size: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(selected.name).font(.body.weight(.medium))
                        if !selected.code.isEmpty {
                            Text(selected.code).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Image(systemName: "books.vertical").foregroundStyle(Theme.accent)
                    Text("Choose a course").foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .card(padding: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Course")
        .accessibilityValue(selected?.name ?? "None chosen")
    }
}

struct PresetGrid: View {
    var configs: [TimerConfig]
    var selectedID: String
    var onSelect: (TimerConfig) -> Void
    var onNew: () -> Void
    var onEdit: (TimerConfig) -> Void
    var onDelete: (TimerConfig) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(configs) { config in
                Button { onSelect(config) } label: {
                    PresetCard(config: config, isSelected: config.id == selectedID)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if !config.isBuiltIn {
                        Button("Edit", systemImage: "pencil") { onEdit(config) }
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete(config) }
                    }
                }
                .accessibilityAddTraits(config.id == selectedID ? .isSelected : [])
            }
            Button(action: onNew) {
                VStack(spacing: 4) {
                    Image(systemName: "plus").font(.title3.weight(.semibold))
                    Text("Custom…").font(.subheadline.weight(.medium))
                }
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 64)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct PresetCard: View {
    var config: TimerConfig
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(config.name).font(.headline).lineLimit(1)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.horizontal, 14)
        .background(
            isSelected ? Theme.accent.opacity(0.14) : Theme.cardBackground,
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2)
        }
    }

    private var detail: String {
        switch config.kind {
        case .stopwatch: "Count up, stop when done"
        case .pomodoro: "\(config.focusMinutes) min focus · \(config.shortBreakMinutes) min break"
        }
    }
}

// MARK: Controls

struct TimerControls: View {
    @Environment(TimerController.self) private var timer
    var onDiscard: () -> Void

    var body: some View {
        let state = timer.state
        VStack(spacing: 12) {
            primaryButton(state)
            HStack(spacing: 12) {
                if canSkip(state) {
                    Button { timer.skip() } label: {
                        Label(state.status == .awaitingStart ? "Skip break" : "Skip", systemImage: "forward.end.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                Button { timer.stop() } label: {
                    Label(state.isStopwatch ? "Finish" : "Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                if state.status == .paused || state.status == .running {
                    Button(role: .destructive, action: onDiscard) {
                        Label("Discard", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func canSkip(_ state: TimerState) -> Bool {
        switch state.status {
        case .running, .paused: !state.isStopwatch
        case .awaitingStart: state.phase.isBreak
        case .idle: false
        }
    }

    @ViewBuilder
    private func primaryButton(_ state: TimerState) -> some View {
        switch state.status {
        case .running:
            Button { timer.pause() } label: {
                Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(state.tint)
        case .paused:
            Button { timer.resume() } label: {
                Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(state.tint)
        case .awaitingStart:
            Button { timer.startNext() } label: {
                Label("Start \(state.phase.title.lowercased())", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(state.tint)
        case .idle:
            EmptyView()
        }
    }
}
