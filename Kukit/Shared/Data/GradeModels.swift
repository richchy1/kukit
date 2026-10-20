import Foundation
import SwiftData
import KukitCore

/// A user-defined grading scale (percent → letter → GPA points). The default one is seeded
/// as "Korean (4.5)" on first launch and can be edited freely.
@Model
final class GradingScale {
    var id: UUID = UUID()
    var name: String = ""
    var gpaMax: Double = 4.5
    var roundingRaw: String = PercentRounding.none.rawValue
    var bands: [GradeBand] = []
    var isDefault: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Course.gradeScale)
    var courses: [Course]?

    init(_ scale: GradeScale, isDefault: Bool = false) {
        self.name = scale.name
        self.gpaMax = scale.gpaMax
        self.roundingRaw = scale.rounding.rawValue
        self.bands = scale.bands
        self.isDefault = isDefault
    }

    /// The pure value used by KukitCore.
    var scale: GradeScale {
        get {
            GradeScale(name: name, gpaMax: gpaMax,
                       rounding: PercentRounding(rawValue: roundingRaw) ?? .none, bands: bands)
        }
        set {
            name = newValue.name
            gpaMax = newValue.gpaMax
            roundingRaw = newValue.rounding.rawValue
            bands = newValue.bands
        }
    }
}

@Model
final class GradeCategory {
    var id: UUID = UUID()
    var name: String = ""
    var weight: Double = 0
    var methodRaw: String = CategoryMethod.totalPoints.rawValue
    var sortOrder: Int = 0

    var course: Course?

    @Relationship(deleteRule: .cascade, inverse: \GradeEntry.category)
    var entries: [GradeEntry]?

    init(name: String, weight: Double, sortOrder: Int = 0, course: Course?) {
        self.name = name
        self.weight = weight
        self.sortOrder = sortOrder
        self.course = course
    }

    var method: CategoryMethod {
        get { CategoryMethod(rawValue: methodRaw) ?? .totalPoints }
        set { methodRaw = newValue.rawValue }
    }

    var input: GradeCategoryInput {
        GradeCategoryInput(id: id, name: name, weight: weight, method: method,
                           entries: (entries ?? []).map(\.input))
    }

    var hasGradedEntries: Bool { (entries ?? []).contains { !$0.isPlanned } }

    /// Percent of graded work only.
    var gradedPercent: Double? {
        GradeCalculator.percent(of: input.gradedEntries, method: method)
    }
}

@Model
final class GradeEntry {
    var id: UUID = UUID()
    var name: String = ""
    var score: Double = 0
    var maxScore: Double = 100
    /// A guess for work that hasn't been graded yet.
    var isPlanned: Bool = false
    var date: Date = Date.now

    var category: GradeCategory?

    @Relationship(deleteRule: .nullify, inverse: \Assignment.gradeEntry)
    var assignment: Assignment?

    init(name: String, score: Double, maxScore: Double, isPlanned: Bool = false,
         date: Date = .now, category: GradeCategory?) {
        self.name = name
        self.score = score
        self.maxScore = maxScore
        self.isPlanned = isPlanned
        self.date = date
        self.category = category
    }

    var input: GradeEntryInput {
        GradeEntryInput(score: score, maxScore: maxScore, isPlanned: isPlanned)
    }

    var percent: Double? { maxScore > 0 ? score * 100 / maxScore : nil }
}

// MARK: - Course helpers

extension Course {
    var sortedCategories: [GradeCategory] {
        (gradeCategories ?? []).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    var categoryInputs: [GradeCategoryInput] { sortedCategories.map(\.input) }
    var gradeSummary: GradeSummary { GradeCalculator.summary(categoryInputs) }
    var hasGrades: Bool { !(gradeCategories ?? []).isEmpty }
}

// MARK: - Scale helpers

enum GradingScales {
    /// Creates the default Korean (4.5) scale on first launch.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<GradingScale>())) ?? 0
        guard count == 0 else { return }
        context.insert(GradingScale(.korean45, isDefault: true))
        try? context.save()
    }

    /// The scale that applies to a course: its own, else the default, else Korean 4.5.
    static func resolve(for course: Course?, in scales: [GradingScale]) -> GradeScale {
        course?.gradeScale?.scale
            ?? scales.first(where: \.isDefault)?.scale
            ?? scales.first?.scale
            ?? .korean45
    }

    static func makeDefault(_ scale: GradingScale, among scales: [GradingScale]) {
        for other in scales { other.isDefault = (other === scale) }
    }

    /// "A+ · 95%" style text for a percent.
    static func letter(for percent: Double?, scale: GradeScale) -> String? {
        percent.flatMap { scale.band(for: $0)?.label }
    }
}

enum CategoryTemplate: String, CaseIterable, Identifiable {
    case standard, examsOnly, korean, quizzes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Homework 20 · Midterm 30 · Final 40 · Participation 10"
        case .examsOnly: "Midterm 40 · Final 60"
        case .korean: "Attendance 10 · Assignments 20 · Midterm 30 · Final 40"
        case .quizzes: "Quizzes 20 · Assignments 20 · Midterm 25 · Final 35"
        }
    }

    var parts: [(String, Double)] {
        switch self {
        case .standard: [("Homework", 20), ("Midterm", 30), ("Final", 40), ("Participation", 10)]
        case .examsOnly: [("Midterm", 40), ("Final", 60)]
        case .korean: [("Attendance", 10), ("Assignments", 20), ("Midterm", 30), ("Final", 40)]
        case .quizzes: [("Quizzes", 20), ("Assignments", 20), ("Midterm", 25), ("Final", 35)]
        }
    }
}
