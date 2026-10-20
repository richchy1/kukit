import SwiftUI
import SwiftData
import KukitCore

enum GradeFormat {
    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

/// Weighted categories, scores, the current/projected grade and the "what do I need?" calculator.
struct CourseGradesView: View {
    @Environment(\.modelContext) private var context
    @Bindable var course: Course
    @Query(sort: \GradingScale.createdAt) private var scales: [GradingScale]

    @State private var sheet: GradeSheet?
    @State private var solveCategoryID: UUID?

    private enum GradeSheet: Identifiable {
        case newCategory
        case editCategory(GradeCategory)
        case newEntry(GradeCategory?)
        case editEntry(GradeEntry)

        var id: String {
            switch self {
            case .newCategory: "newCategory"
            case .editCategory(let c): "cat-\(c.id)"
            case .newEntry(let c): "newEntry-\(c?.id.uuidString ?? "none")"
            case .editEntry(let e): "entry-\(e.id)"
            }
        }
    }

    private var scale: GradeScale { GradingScales.resolve(for: course, in: scales) }
    private var categories: [GradeCategory] { course.sortedCategories }
    private var summary: GradeSummary { GradeCalculator.summary(course.categoryInputs) }

    /// The category the calculator solves for: the user's pick, else the heaviest one with no graded work.
    private var solveCategory: GradeCategory? {
        if let id = solveCategoryID, let picked = categories.first(where: { $0.id == id }) { return picked }
        return categories.filter { !$0.hasGradedEntries }.max { $0.weight < $1.weight } ?? categories.last
    }

    var body: some View {
        List {
            Section {
                summaryCards
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if !categories.isEmpty, abs(summary.totalWeight - 100) > 0.001 {
                Section {
                    Label("Weights add up to \(GradeFormat.number(summary.totalWeight))%, not 100%. Grades are scaled to match.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            if categories.isEmpty {
                setupSection
            } else {
                ForEach(categories) { category in categorySection(category) }
                whatIfSection
                Section {
                    Button("Add category", systemImage: "plus") { sheet = .newCategory }
                }
            }
        }
        .navigationTitle("Grades")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !categories.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add score", systemImage: "plus") { sheet = .newEntry(nil) }
                }
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .newCategory: GradeCategoryEditorView(course: course, category: nil)
            case .editCategory(let category): GradeCategoryEditorView(course: course, category: category)
            case .newEntry(let category): GradeEntryEditorView(course: course, entry: nil, defaultCategory: category)
            case .editEntry(let entry): GradeEntryEditorView(course: course, entry: entry, defaultCategory: nil)
            }
        }
    }

    // MARK: Summary

    private var summaryCards: some View {
        let band = summary.currentPercent.flatMap { scale.band(for: $0) }
        let projectedBand = summary.projectedPercent.flatMap { scale.band(for: $0) }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
            gradeTile(title: "Now", percent: summary.currentPercent, band: band)
            gradeTile(title: "Projected", percent: summary.projectedPercent, band: projectedBand)
            StatTile(title: "Locked in", value: "\(GradeFormat.number(summary.lockedInPoints)) pts")
        }
        .padding(.vertical, 4)
    }

    private func gradeTile(title: String, percent: Double?, band: GradeBand?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(GradeFormat.percent(percent))
                    .font(.title2.weight(.semibold)).monospacedDigit()
                    .minimumScaleFactor(0.7).lineLimit(1)
                if let band {
                    Text(band.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(course.color)
                }
            }
            if let band {
                Text("\(GradeFormat.number(band.gpaPoints)) / \(GradeFormat.number(scale.gpaMax))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: Categories

    private var setupSection: some View {
        Section {
            EmptyStateView(
                systemImage: "percent",
                title: "Set up grading",
                message: "Add the parts of the grade (homework, midterm, final…) with their weights, then enter scores as they come in."
            )
            Menu {
                ForEach(CategoryTemplate.allCases) { template in
                    Button(template.title) { apply(template) }
                }
            } label: {
                Label("Start from a template", systemImage: "wand.and.stars")
            }
            Button("Add category yourself", systemImage: "plus") { sheet = .newCategory }
        }
    }

    private func categorySection(_ category: GradeCategory) -> some View {
        let entries = (category.entries ?? []).sorted { $0.date > $1.date }
        let percent = GradeCalculator.percent(of: category.input.entries, method: category.method)
        return Section {
            if entries.isEmpty {
                Text("No scores yet").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                Button { sheet = .editEntry(entry) } label: { entryRow(entry) }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            context.delete(entry)
                            try? context.save()
                        }
                    }
            }
            Button("Add score", systemImage: "plus") { sheet = .newEntry(category) }
                .font(.subheadline)
        } header: {
            Button { sheet = .editCategory(category) } label: {
                HStack {
                    Text(category.name).font(.headline).foregroundStyle(.primary)
                    Text("\(GradeFormat.number(category.weight))%")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(course.color.opacity(0.18), in: Capsule())
                    Spacer()
                    Text(GradeFormat.percent(percent))
                        .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                    Image(systemName: "pencil").font(.caption).foregroundStyle(.tertiary)
                }
                .textCase(nil)
            }
            .buttonStyle(.plain)
        }
    }

    private func entryRow(_ entry: GradeEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name.isEmpty ? "Score" : entry.name).font(.body)
                if entry.isPlanned {
                    Text("Planned").font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text("\(GradeFormat.number(entry.score)) / \(GradeFormat.number(entry.maxScore))")
                .monospacedDigit()
            Text(GradeFormat.percent(entry.percent))
                .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .trailing)
        }
        .foregroundStyle(entry.isPlanned ? .secondary : .primary)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: What-if

    private var whatIfSection: some View {
        Section {
            if let target = solveCategory {
                Stepper(value: $course.targetPercent, in: 0...100, step: 0.5) {
                    let band = scale.band(for: course.targetPercent)
                    Text("Target \(GradeFormat.percent(course.targetPercent))\(band.map { " (\($0.label))" } ?? "")")
                }
                Menu {
                    ForEach(scale.bands.sorted { $0.minPercent > $1.minPercent }) { band in
                        Button("\(band.label) · \(GradeFormat.number(band.minPercent))%") {
                            course.targetPercent = band.minPercent
                        }
                    }
                } label: {
                    Label("Pick a target grade", systemImage: "target")
                }
                Picker("Solve for", selection: Binding(
                    get: { target.id },
                    set: { solveCategoryID = $0 }
                )) {
                    ForEach(categories) { Text($0.name).tag($0.id) }
                }

                let result = GradeCalculator.requiredPercent(
                    target: course.targetPercent, in: target.id, categories: course.categoryInputs
                )
                requiredLabel(result, categoryName: target.name)

                ForEach(categories.filter { !$0.hasGradedEntries }) { category in
                    plannedSlider(category)
                }

                if let best = summary.bestCasePercent, let worst = summary.worstCasePercent {
                    HStack {
                        Label("Best case \(GradeFormat.percent(best))", systemImage: "arrow.up.right")
                        Spacer()
                        Label("Worst case \(GradeFormat.percent(worst))", systemImage: "arrow.down.right")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("What do I need?")
        } footer: {
            Text("Use the sliders to guess the scores you haven't received yet. The projected grade above updates as you move them.")
        }
    }

    @ViewBuilder
    private func requiredLabel(_ result: RequiredScore, categoryName: String) -> some View {
        switch result {
        case .needs(let value):
            Label("You need \(GradeFormat.percent(value)) on \(categoryName).", systemImage: "scope")
                .font(.headline)
                .foregroundStyle(course.color)
        case .secured:
            Label("Secured: you reach \(GradeFormat.percent(course.targetPercent)) even with 0% on \(categoryName).",
                  systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .unreachable(let best):
            Label("Out of reach: even 100% on \(categoryName) gives at most \(GradeFormat.percent(best)).",
                  systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .noWeight:
            Label("\(categoryName) has no weight.", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        case .noData:
            Label("Add scores or planned scores for the other categories first.", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func plannedSlider(_ category: GradeCategory) -> some View {
        let planned = (category.entries ?? []).first { $0.isPlanned }
        let fallback = summary.currentPercent ?? 80
        let value = planned?.percent ?? fallback
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(category.name) (guess)")
                Spacer()
                Text(GradeFormat.percent(planned == nil ? nil : value))
                    .monospacedDigit().foregroundStyle(.secondary)
                if planned != nil {
                    Button("Clear") { clearPlanned(category) }
                        .font(.footnote).buttonStyle(.borderless)
                }
            }
            Slider(value: Binding(
                get: { value },
                set: { setPlanned(category, percent: $0.rounded()) }
            ), in: 0...100, step: 1)
            .tint(course.color)
        }
        .padding(.vertical, 2)
    }

    private func setPlanned(_ category: GradeCategory, percent: Double) {
        if let planned = (category.entries ?? []).first(where: { $0.isPlanned }) {
            planned.score = percent * planned.maxScore / 100
        } else {
            context.insert(GradeEntry(name: "Planned", score: percent, maxScore: 100, isPlanned: true, category: category))
        }
    }

    private func clearPlanned(_ category: GradeCategory) {
        for entry in category.entries ?? [] where entry.isPlanned && entry.assignment == nil {
            context.delete(entry)
        }
        try? context.save()
    }

    private func apply(_ template: CategoryTemplate) {
        for (index, part) in template.parts.enumerated() {
            context.insert(GradeCategory(name: part.0, weight: part.1, sortOrder: index, course: course))
        }
        try? context.save()
    }
}
