import SwiftUI
import SwiftData
import KukitCore

/// Create or edit a custom timer technique (name, durations, rounds).
struct PresetEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TimerController.self) private var timer
    @Query private var existing: [TimerPreset]

    var preset: TimerPreset?

    @State private var name: String
    @State private var focus: Int
    @State private var shortBreak: Int
    @State private var longBreak: Int
    @State private var rounds: Int

    init(preset: TimerPreset?) {
        self.preset = preset
        _name = State(initialValue: preset?.name ?? "")
        _focus = State(initialValue: preset?.focusMinutes ?? 40)
        _shortBreak = State(initialValue: preset?.shortBreakMinutes ?? 8)
        _longBreak = State(initialValue: preset?.longBreakMinutes ?? 20)
        _rounds = State(initialValue: preset?.roundsBeforeLongBreak ?? 4)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                KSection("Name") {
                    TextField("e.g. Night owl", text: $name)
                }
                KSection("Durations") {
                    NumberRow(title: "Focus", unit: "min", value: $focus, range: TimerConfig.focusRange)
                    NumberRow(title: "Short break", unit: "min", value: $shortBreak, range: TimerConfig.shortBreakRange)
                    NumberRow(title: "Long break", unit: "min", value: $longBreak, range: TimerConfig.longBreakRange)
                    NumberRow(title: "Long break after", unit: "rounds", value: $rounds, range: TimerConfig.roundsRange)
                }
                KSection {
                    Text("\(focus) min focus, then \(shortBreak) min break. After \(rounds) rounds, a \(longBreak) min break.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .kukitList()
            .navigationTitle(preset == nil ? "New technique" : "Edit technique")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(trimmedName.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
        #endif
    }

    private func save() {
        let clamped = TimerConfig(
            name: trimmedName, focusMinutes: focus, shortBreakMinutes: shortBreak,
            longBreakMinutes: longBreak, roundsBeforeLongBreak: rounds
        ).clamped()

        let target: TimerPreset
        if let preset {
            target = preset
        } else {
            target = TimerPreset(name: trimmedName, sortOrder: existing.count)
            context.insert(target)
        }
        target.name = clamped.name
        target.focusMinutes = clamped.focusMinutes
        target.shortBreakMinutes = clamped.shortBreakMinutes
        target.longBreakMinutes = clamped.longBreakMinutes
        target.roundsBeforeLongBreak = clamped.roundsBeforeLongBreak
        try? context.save()
        timer.selectPreset(target.config)
        dismiss()
    }
}

/// A labeled number field with a stepper; typed values are clamped to `range`.
struct NumberRow: View {
    var title: String
    var unit: String
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: $value, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onChange(of: value) { _, new in
                    let clamped = min(max(new, range.lowerBound), range.upperBound)
                    if clamped != new { value = clamped }
                }
            Text(unit).foregroundStyle(.secondary)
            Stepper(title, value: $value, in: range).labelsHidden()
        }
        .accessibilityElement(children: .combine)
    }
}
