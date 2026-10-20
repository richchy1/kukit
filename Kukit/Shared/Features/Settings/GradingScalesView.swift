import SwiftUI
import SwiftData
import KukitCore

/// Settings ▸ Grading scales: define as many scales as you need; one is the default.
struct GradingScalesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \GradingScale.createdAt) private var scales: [GradingScale]
    @State private var editing: GradingScale?

    var body: some View {
        List {
            Section {
                ForEach(scales) { scale in
                    Button { editing = scale } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(scale.name).foregroundStyle(.primary)
                                    if scale.isDefault {
                                        Text("Default").font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(Theme.accent.opacity(0.18), in: Capsule())
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                Text("\(scale.bands.count) bands · max \(GradeFormat.number(scale.gpaMax)) · \((scale.courses ?? []).count) courses")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("A course uses the default scale unless you choose another one in the course's settings.")
            }
        }
        .navigationTitle("Grading scales")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("New scale", systemImage: "plus") {
                    Button("Copy of the default scale") { create(from: scales.first(where: \.isDefault)?.scale ?? .korean45) }
                    Button("Korean (4.5) template") { create(from: .korean45) }
                    Button("Blank scale") {
                        create(from: GradeScale(name: "New scale", gpaMax: 4, bands: [
                            GradeBand(minPercent: 50, label: "Pass", gpaPoints: 4),
                            GradeBand(minPercent: 0, label: "Fail", gpaPoints: 0),
                        ]))
                    }
                }
            }
        }
        .sheet(item: $editing) { GradeScaleEditorView(model: $0, allScales: scales) }
    }

    private func create(from template: GradeScale) {
        var copy = template
        copy.name = uniqueName(template.name)
        copy.bands = copy.bands.map { GradeBand(minPercent: $0.minPercent, label: $0.label, gpaPoints: $0.gpaPoints) }
        let model = GradingScale(copy, isDefault: scales.isEmpty)
        context.insert(model)
        try? context.save()
        editing = model
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(scales.map(\.name))
        guard names.contains(base) else { return base }
        var index = 2
        while names.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }
}

struct GradeScaleEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let model: GradingScale
    let allScales: [GradingScale]

    @State private var draft: GradeScale
    @State private var makeDefault: Bool
    @State private var previewText = "87"
    @State private var confirmDelete = false

    init(model: GradingScale, allScales: [GradingScale]) {
        self.model = model
        self.allScales = allScales
        _draft = State(initialValue: model.scale)
        _makeDefault = State(initialValue: model.isDefault)
    }

    private var issues: [ScaleIssue] { draft.issues() }
    private var canDelete: Bool { allScales.count > 1 && !model.isDefault }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Scale name", text: $draft.name)
                    HStack {
                        Text("GPA maximum")
                        Spacer()
                        TextField("", value: $draft.gpaMax, format: .number)
                            .multilineTextAlignment(.trailing).frame(width: 70)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    Picker("Round percent", selection: $draft.rounding) {
                        Text("Don't round").tag(PercentRounding.none)
                        Text("To the nearest whole %").tag(PercentRounding.nearest)
                    }
                } footer: {
                    Text("Rounding is applied to a course's percent before looking up its letter.")
                }

                Section {
                    ForEach($draft.bands) { $band in
                        HStack(spacing: 8) {
                            TextField("%", value: $band.minPercent, format: .number)
                                .frame(width: 52).multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Text("→").foregroundStyle(.secondary)
                            TextField("Label", text: $band.label).frame(minWidth: 50)
                            Spacer(minLength: 4)
                            TextField("GPA", value: $band.gpaPoints, format: .number)
                                .frame(width: 52).multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Button {
                                draft.bands.removeAll { $0.id == band.id }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove band \(band.label)")
                        }
                    }
                    Button("Add band", systemImage: "plus") {
                        let next = (draft.bands.map(\.minPercent).filter { $0 > 0 }.min() ?? 100) - 5
                        draft.bands.append(GradeBand(minPercent: max(1, next), label: "", gpaPoints: 0))
                    }
                } header: {
                    HStack {
                        Text("From %")
                        Spacer()
                        Text("Label · GPA points")
                    }
                } footer: {
                    Text("A percent gets the highest band whose “From %” it reaches. The lowest band must start at 0.")
                }

                Section("Try it") {
                    HStack {
                        TextField("Percent", text: $previewText)
                            .frame(width: 80)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Spacer()
                        Text(previewResult).font(.headline).monospacedDigit()
                    }
                }

                if !issues.isEmpty {
                    Section {
                        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    Toggle("Use as the default scale", isOn: $makeDefault)
                        .disabled(model.isDefault)
                    if canDelete {
                        Button("Delete scale…", role: .destructive) { confirmDelete = true }
                    }
                } footer: {
                    if model.isDefault {
                        Text("To change the default, open another scale and switch this on there.")
                    } else if (model.courses ?? []).count > 0 {
                        Text("\((model.courses ?? []).count) courses use this scale. If you delete it they switch to the default.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit scale")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!issues.isEmpty || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete \(model.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete scale", role: .destructive) {
                    context.delete(model)
                    try? context.save()
                    dismiss()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 640)
        #endif
    }

    private var previewResult: String {
        let cleaned = previewText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), let band = draft.band(for: value) else { return "–" }
        return "\(band.label) · \(GradeFormat.number(band.gpaPoints)) / \(GradeFormat.number(draft.gpaMax))"
    }

    private func save() {
        var cleaned = draft
        cleaned.name = cleaned.name.trimmingCharacters(in: .whitespaces)
        cleaned.bands = cleaned.bands
            .map { GradeBand(id: $0.id, minPercent: $0.minPercent, label: $0.label.trimmingCharacters(in: .whitespaces), gpaPoints: $0.gpaPoints) }
            .sorted { $0.minPercent > $1.minPercent }
        model.scale = cleaned
        if makeDefault && !model.isDefault { GradingScales.makeDefault(model, among: allScales) }
        try? context.save()
        dismiss()
    }
}
