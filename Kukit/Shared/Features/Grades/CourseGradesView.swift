import SwiftUI
import SwiftData
import Charts
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

/// Weighted categories, scores, the current/projected grade and the "what do I need?" answer.
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

    private static let cardInsets = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)

    var body: some View {
        List {
            if categories.isEmpty {
                setupSection
            } else {
                clearRow { finalAnswerCard }
                clearRow { summaryCards }
                clearRow { breakdownCard }

                if abs(summary.totalWeight - 100) > 0.001 {
                    KSection {
                        Label("Weights add up to \(GradeFormat.number(summary.totalWeight))%, not 100%. Grades are scaled to match.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.kukit(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.accentText)
                    }
                }

                ForEach(categories) { category in categorySection(category) }
                planSection
                KSection {
                    Button("Add category", systemImage: "plus") { sheet = .newCategory }
                        .buttonStyle(.kukit(.ghost))
                }
            }
        }
        .kukitList()
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

    /// A list row with no row chrome, so a card can stand on its own.
    private func clearRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .listRowInsets(Self.cardInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    // MARK: "What do I need on the final?"

    private var finalAnswerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("What do I need on the final?", systemImage: "scope")
                .font(.kukit(.subheadline, weight: .heavy))
                .foregroundStyle(Theme.accentText)

            if let target = solveCategory {
                let result = GradeCalculator.requiredPercent(
                    target: course.targetPercent, in: target.id, categories: course.categoryInputs
                )
                answer(result, categoryName: target.name)

                Divider().opacity(0.6)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { targetControls; solveControl(target) }
                    VStack(alignment: .leading, spacing: 10) { targetControls; solveControl(target) }
                }
            }
        }
        .card(padding: 18, tone: .accent)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func answer(_ result: RequiredScore, categoryName: String) -> some View {
        let targetBand = scale.band(for: course.targetPercent)
        let targetText = "\(GradeFormat.percent(course.targetPercent))\(targetBand.map { " (\($0.label))" } ?? "")"
        switch result {
        case .needs(let value):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(GradeFormat.percent(value))
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                VStack(alignment: .leading, spacing: 2) {
                    Text("on \(categoryName)").font(.kukit(.headline, weight: .heavy))
                    Text("to finish with \(targetText)").font(.kukit(.subheadline, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        case .secured:
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Already in the bag").font(.kukit(.headline, weight: .heavy))
                    Text("You reach \(targetText) even with 0% on \(categoryName).")
                        .font(.kukit(.subheadline, weight: .medium)).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "checkmark.seal.fill").font(.title).foregroundStyle(Theme.basil)
            }
        case .unreachable(let best):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Out of reach for \(targetText)").font(.kukit(.headline, weight: .heavy))
                    Text("Even 100% on \(categoryName) gives at most \(GradeFormat.percent(best)).")
                        .font(.kukit(.subheadline, weight: .medium)).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").font(.title).foregroundStyle(Theme.accent)
            }
        case .noWeight:
            Text("\(categoryName) has no weight, so it can't change your grade.")
                .font(.kukit(.subheadline, weight: .medium)).foregroundStyle(.secondary)
        case .noData:
            Text("Add scores (or guesses below) for the other categories and the answer shows up here.")
                .font(.kukit(.subheadline, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    private var targetControls: some View {
        HStack(spacing: 8) {
            Text("Target").font(.kukit(.subheadline, weight: .bold))
            Stepper(value: $course.targetPercent, in: 0...100, step: 0.5) {
                Text(GradeFormat.percent(course.targetPercent)).font(.kukit(.subheadline, weight: .heavy)).monospacedDigit()
            }
            .fixedSize()
            Menu {
                ForEach(scale.bands.sorted { $0.minPercent > $1.minPercent }) { band in
                    Button("\(band.label) · \(GradeFormat.number(band.minPercent))%") {
                        course.targetPercent = band.minPercent
                    }
                }
            } label: {
                Label(scale.band(for: course.targetPercent)?.label ?? "Grade", systemImage: "target")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func solveControl(_ target: GradeCategory) -> some View {
        HStack(spacing: 8) {
            Text("Solve for").font(.kukit(.subheadline, weight: .bold))
            Picker("Solve for", selection: Binding(get: { target.id }, set: { solveCategoryID = $0 })) {
                ForEach(categories) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    // MARK: Summary & chart

    private var summaryCards: some View {
        let band = summary.currentPercent.flatMap { scale.band(for: $0) }
        let projectedBand = summary.projectedPercent.flatMap { scale.band(for: $0) }
        return VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                gradeTile(title: "Now", percent: summary.currentPercent, band: band)
                gradeTile(title: "Projected", percent: summary.projectedPercent, band: projectedBand)
                StatTile(title: "Locked in", value: "\(GradeFormat.number(summary.lockedInPoints)) pts", systemImage: "lock.fill")
            }
            if let best = summary.bestCasePercent, let worst = summary.worstCasePercent {
                HStack(spacing: 12) {
                    StatTile(title: "Best case", value: GradeFormat.percent(best), systemImage: "arrow.up.right", tint: Theme.basilText)
                    StatTile(title: "Worst case", value: GradeFormat.percent(worst), systemImage: "arrow.down.right", tint: Theme.accentText)
                }
            }
        }
    }

    private func gradeTile(title: String, percent: Double?, band: GradeBand?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.kukit(.caption, weight: .semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(GradeFormat.percent(percent))
                    .font(.kukit(.title2, weight: .heavy)).monospacedDigit()
                    .minimumScaleFactor(0.7).lineLimit(1)
                if let band {
                    Text(band.label).font(.kukit(.headline, weight: .heavy)).foregroundStyle(course.color)
                }
            }
            if let band {
                Text("\(GradeFormat.number(band.gpaPoints)) / \(GradeFormat.number(scale.gpaMax))")
                    .font(.kukit(.caption2, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private struct Slice: Identifiable {
        enum Kind: String { case earned = "Earned", lost = "Lost", pending = "Still to cook" }
        var category: String
        var kind: Kind
        var points: Double
        var id: String { category + kind.rawValue }
    }

    /// Where the 100 points come from: earned, lost, or still on the stove, per category.
    private var slices: [Slice] {
        let total = summary.totalWeight
        guard total > 0 else { return [] }
        var result: [Slice] = []
        for category in categories where category.weight > 0 {
            let possible = category.weight * 100 / total
            if let graded = category.gradedPercent {
                let earned = possible * min(max(graded, 0), 100) / 100
                result.append(Slice(category: category.name, kind: .earned, points: earned))
                result.append(Slice(category: category.name, kind: .lost, points: possible - earned))
            } else {
                result.append(Slice(category: category.name, kind: .pending, points: possible))
            }
        }
        return result
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Where your points come from", systemImage: "chart.bar.xaxis")
            Chart(slices) { slice in
                BarMark(x: .value("Points", slice.points), y: .value("Category", slice.category))
                    .foregroundStyle(by: .value("Status", slice.kind.rawValue))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale([
                Slice.Kind.earned.rawValue: Theme.basil,
                Slice.Kind.lost.rawValue: Theme.accent.opacity(0.35),
                Slice.Kind.pending.rawValue: Theme.butter,
            ])
            .chartXAxisLabel("Points out of 100")
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: max(120, CGFloat(categories.count) * 38 + 60))
            .accessibilityLabel("Points earned, lost and still to come for each grading category")
        }
        .card(padding: 18)
    }

    // MARK: Categories

    private var setupSection: some View {
        KSection {
            EmptyStateView(
                mood: .idle, title: "Set up the recipe",
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
                .buttonStyle(.kukit(.ghost))
        }
    }

    private func categorySection(_ category: GradeCategory) -> some View {
        let entries = (category.entries ?? []).sorted { $0.date > $1.date }
        let percent = GradeCalculator.percent(of: category.input.entries, method: category.method)
        return KSection {
            if entries.isEmpty {
                Text("No scores yet").font(.kukit(.footnote, weight: .medium)).foregroundStyle(.secondary)
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
                .buttonStyle(.kukit(.ghost))
        } header: {
            Button { sheet = .editCategory(category) } label: {
                HStack {
                    Text(category.name).font(.kukit(.headline, weight: .heavy)).foregroundStyle(Theme.ink)
                    Text("\(GradeFormat.number(category.weight))%")
                        .font(.kukit(.caption, weight: .heavy))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(course.color.opacity(0.18), in: Capsule())
                    Spacer()
                    Text(GradeFormat.percent(percent))
                        .font(.kukit(.subheadline, weight: .bold)).monospacedDigit().foregroundStyle(.secondary)
                    Image(systemName: "pencil").font(.caption).foregroundStyle(.tertiary)
                }
                .textCase(nil)
            }
            .buttonStyle(.plain)
        }
    }

    private func entryRow(_ entry: GradeEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name.isEmpty ? "Score" : entry.name).font(.kukit(.body, weight: .semibold))
                if entry.isPlanned {
                    Chip(text: "Planned", systemImage: "lightbulb.fill", tint: Color(hex: "9A6B00"))
                }
            }
            Spacer()
            Text("\(GradeFormat.number(entry.score)) / \(GradeFormat.number(entry.maxScore))")
                .font(.kukit(.body, weight: .bold)).monospacedDigit()
            Text(GradeFormat.percent(entry.percent))
                .font(.kukit(.footnote, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .trailing)
        }
        .foregroundStyle(entry.isPlanned ? Color.secondary : Theme.ink)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Plan the rest

    @ViewBuilder
    private var planSection: some View {
        let open = categories.filter { !$0.hasGradedEntries }
        if !open.isEmpty {
            KSection {
                ForEach(open) { category in plannedSlider(category) }
            } header: {
                Text("Plan the rest")
            } footer: {
                Text("Guess the scores you haven't received yet. The projected grade and the answer above update as you move the sliders.")
            }
        }
    }

    private func plannedSlider(_ category: GradeCategory) -> some View {
        let planned = (category.entries ?? []).first { $0.isPlanned }
        let fallback = summary.currentPercent ?? 80
        let value = planned?.percent ?? fallback
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(category.name) (guess)").font(.kukit(.body, weight: .semibold))
                Spacer()
                Text(GradeFormat.percent(planned == nil ? nil : value))
                    .font(.kukit(.body, weight: .heavy)).monospacedDigit().foregroundStyle(.secondary)
                if planned != nil {
                    Button("Clear") { clearPlanned(category) }.buttonStyle(.kukit(.ghost))
                }
            }
            Slider(value: Binding(
                get: { value },
                set: { setPlanned(category, percent: $0.rounded()) }
            ), in: 0...100, step: 1)
            .tint(Theme.accent)
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
