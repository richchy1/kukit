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
            if phase == .focus { return "Round \(round) of \(config.roundsBeforeLongBreak)" }
            return phase.title
        }
    }

    var tint: Color {
        phase.isBreak ? Theme.basil : Theme.accent
    }

    /// How Chef Kukit looks for this moment of the session.
    /// A date the digits' one-second ticks can line up with, so the display flips exactly when
    /// the second changes (and the screen redraws once per second, not twice).
    var tickAnchor: Date {
        if let end = endDate { return end }
        if let since = runningSince { return since.addingTimeInterval(-accumulated) }
        return Date(timeIntervalSinceReferenceDate: 0)
    }

    func chefMood(at now: Date) -> ChefMood {
        switch status {
        case .idle: return .idle
        case .paused: return .idle
        case .awaitingStart: return phase.isBreak ? .breakTime : .ready
        case .running:
            if phase.isBreak { return .breakTime }
            return now.timeIntervalSince(phaseStartedAt) < 8 ? .ready : .working
        }
    }

    /// Chef Kukit's line for this moment: a send-off at the start, then occasional encouragement.
    func chefLine(at now: Date) -> String {
        let seed = Int(phaseStartedAt.timeIntervalSince1970 / 60)
        switch status {
        case .idle:
            return "Pick a course and a technique, then start cooking."
        case .paused:
            return "Paused. The stove is off, the chef is waiting."
        case .awaitingStart:
            return phase.isBreak ? Chef.line(.breakTime, seed: seed) : "Ready when you are, chef."
        case .running:
            if phase.isBreak { return Chef.line(.breakTime, seed: seed) }
            let elapsed = now.timeIntervalSince(phaseStartedAt)
            if elapsed < 8 { return Chef.line(.sessionStart, seed: seed) }
            return Chef.line(.working, seed: seed + Int(elapsed / 300))
        }
    }
}

// MARK: - Ring

/// The big dial + digits. The digits redraw once a second; the dial's arc only every few seconds
/// (it moves a hair per second), which keeps a running timer cheap.
struct TimerRingView: View {
    @Environment(TimerController.self) private var timer
    var idleConfig: TimerConfig
    var courseColor: Color?
    var digitSize: CGFloat = 60
    var lineWidth: CGFloat = 14
    var showsSubtitle = true

    var body: some View {
        let state = timer.state
        let tint = state.isActive && state.phase.isBreak ? Theme.basil : (courseColor ?? Theme.accent)
        ZStack {
            TimelineView(.periodic(from: state.tickAnchor, by: 5)) { context in
                SimmerRing(
                    progress: state.isActive ? state.progress(at: context.date) : 0,
                    tint: tint, isRunning: state.status == .running, lineWidth: lineWidth
                )
            }
            VStack(spacing: 4) {
                TimelineView(.periodic(from: state.tickAnchor, by: 1)) { context in
                    TimerDigits(text: digits(state, now: context.date), size: digitSize)
                        .foregroundStyle(Theme.ink)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(state.isActive ? "\(state.phase.title), \(state.subtitle)" : "Timer ready")
                        .accessibilityValue(spoken(state, now: context.date))
                }
                if showsSubtitle {
                    Text(state.isActive ? state.subtitle : "Ready")
                        .font(.kukit(.subheadline, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, lineWidth * 1.8)
        }
    }

    private func digits(_ state: TimerState, now: Date) -> String {
        guard state.isActive else {
            return idleConfig.kind == .stopwatch ? "00:00" : DurationFormat.clock(TimeInterval(idleConfig.focusMinutes * 60))
        }
        if let remaining = state.remaining(at: now) { return DurationFormat.clock(remaining) }
        return DurationFormat.clock(state.elapsed(at: now).rounded(.down))   // stopwatch counts up
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

// MARK: - Pickers

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
                    CourseBadge(color: selected.color, symbol: selected.symbolName, size: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(selected.name).font(.kukit(.body, weight: .bold)).foregroundStyle(Theme.ink)
                        if !selected.code.isEmpty {
                            Text(selected.code).font(.kukit(.caption, weight: .medium)).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Image(systemName: "books.vertical.fill").foregroundStyle(Theme.accent)
                    Text("Choose a course").font(.kukit(.body, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Theme.softBackgroundFaint, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel("Course")
        .accessibilityValue(selected?.name ?? "None chosen")
    }
}

/// A compact technique picker for the dashboard card.
struct TechniqueMenu: View {
    var configs: [TimerConfig]
    var selected: TimerConfig
    var onSelect: (TimerConfig) -> Void

    var body: some View {
        Menu {
            ForEach(configs) { config in
                Button { onSelect(config) } label: {
                    if config.id == selected.id {
                        Label("\(config.name) · \(config.summary)", systemImage: "checkmark")
                    } else {
                        Text("\(config.name) · \(config.summary)")
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected.kind == .stopwatch ? "stopwatch.fill" : "timer")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(selected.name).font(.kukit(.subheadline, weight: .bold)).foregroundStyle(Theme.ink)
                    Text(selected.summary).font(.kukit(.caption2, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Theme.softBackgroundFaint, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border) }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel("Technique")
        .accessibilityValue(selected.name)
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
                .hoverHighlight(radius: Theme.controlRadius)
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
                    Image(systemName: "plus").font(.title3.weight(.bold))
                    Text("Custom…").font(.kukit(.subheadline, weight: .bold))
                }
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity, minHeight: 68)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                }
            }
            .buttonStyle(.plain)
            .hoverHighlight()
        }
    }
}

struct PresetCard: View {
    var config: TimerConfig
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: config.kind == .stopwatch ? "stopwatch.fill" : "flame.fill")
                .font(.title3)
                .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name).font(.kukit(.headline, weight: .heavy)).lineLimit(1).foregroundStyle(Theme.ink)
                Text(detail).font(.kukit(.caption, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .padding(.horizontal, 14)
        .background(
            isSelected ? Theme.softBackground.opacity(0.7) : Theme.cardBackground,
            in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 2 : 1)
        }
    }

    private var detail: String {
        switch config.kind {
        case .stopwatch: "Count up, stop when done"
        case .pomodoro: "\(config.focusMinutes) min · \(config.shortBreakMinutes) min break"
        }
    }
}

// MARK: - Controls

struct TimerControls: View {
    @Environment(TimerController.self) private var timer
    /// Asks the screen to confirm cancelling.
    var onCancel: () -> Void

    var body: some View {
        let state = timer.state
        VStack(spacing: 10) {
            primaryButton(state)
            HStack(spacing: 8) {
                if canSkip(state) {
                    Button { timer.skip() } label: {
                        Label(state.status == .awaitingStart ? "Skip break" : "Skip", systemImage: "forward.end.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.kukit(.secondary))
                }
                Button { timer.stop() } label: {
                    Label("Finish", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.kukit(.secondary))
                .accessibilityHint("Ends the session and saves your focus time")
                Button(action: onCancel) {
                    Label("Cancel", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.kukit(.danger))
                .accessibilityHint("Ends the session without saving")
            }
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
            Button { Haptics.play(.tap); timer.pause() } label: {
                Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.kukit(.primary, tint: state.tint))
        case .paused:
            Button { Haptics.play(.tap); timer.resume() } label: {
                Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.kukit(.primary, tint: state.tint))
        case .awaitingStart:
            Button { Haptics.play(.heavy); timer.startNext() } label: {
                Label(state.phase.isBreak ? "Start break" : "Start cooking", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.kukit(.primary, tint: state.tint))
        case .idle:
            EmptyView()
        }
    }
}
