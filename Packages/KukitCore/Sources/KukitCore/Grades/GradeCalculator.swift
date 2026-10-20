import Foundation

public enum CategoryMethod: String, Codable, Sendable, CaseIterable {
    /// Σ score / Σ max — bigger assignments count for more.
    case totalPoints
    /// The mean of each entry's percent — every entry counts equally.
    case averageOfPercentages
}

public struct GradeEntryInput: Equatable, Sendable {
    public var score: Double
    public var maxScore: Double
    /// A guess for work that hasn't been graded yet.
    public var isPlanned: Bool

    public init(score: Double, maxScore: Double, isPlanned: Bool = false) {
        self.score = score
        self.maxScore = maxScore
        self.isPlanned = isPlanned
    }
}

public struct GradeCategoryInput: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// Weight of the category (normally the weights add up to 100).
    public var weight: Double
    public var method: CategoryMethod
    public var entries: [GradeEntryInput]

    public init(id: UUID = UUID(), name: String, weight: Double,
                method: CategoryMethod = .totalPoints, entries: [GradeEntryInput]) {
        self.id = id
        self.name = name
        self.weight = weight
        self.method = method
        self.entries = entries
    }

    public var gradedEntries: [GradeEntryInput] { entries.filter { !$0.isPlanned } }
}

public struct GradeSummary: Equatable, Sendable {
    /// Σ of all category weights.
    public var totalWeight: Double
    /// Grade from graded work only, scaled to the weight completed so far. Nil with no graded work.
    public var currentPercent: Double?
    /// Percentage points of the final grade already earned (out of 100 when weights add to 100).
    public var lockedInPoints: Double
    /// Weight that has graded work.
    public var gradedWeight: Double
    /// Graded + planned work; categories with nothing at all are assumed to match `currentPercent`.
    public var projectedPercent: Double?
    public var assumedCategoryIDs: Set<UUID>
    /// Everything not yet graded scores 100 %.
    public var bestCasePercent: Double?
    /// Everything not yet graded scores 0 %.
    public var worstCasePercent: Double?
}

public enum RequiredScore: Equatable, Sendable {
    /// The target is reached even with a 0 in this category.
    case secured
    /// The percent needed in the chosen category.
    case needs(Double)
    /// Even 100 % isn't enough; this is the best possible final grade.
    case unreachable(maxPossible: Double)
    /// The chosen category has no weight.
    case noWeight
    /// Other categories have no data to base the calculation on.
    case noData
}

public enum GradeCalculator {
    /// Percent for a list of entries, or nil when there is nothing to measure.
    public static func percent(of entries: [GradeEntryInput], method: CategoryMethod) -> Double? {
        let usable = entries.filter { $0.maxScore > 0 }
        guard !usable.isEmpty else { return nil }
        switch method {
        case .totalPoints:
            let earned = usable.reduce(0) { $0 + $1.score }
            let possible = usable.reduce(0) { $0 + $1.maxScore }
            return earned * 100 / possible
        case .averageOfPercentages:
            let sum = usable.reduce(0) { $0 + $1.score * 100 / $1.maxScore }
            return sum / Double(usable.count)
        }
    }

    public static func summary(_ categories: [GradeCategoryInput]) -> GradeSummary {
        let cats = categories.filter { $0.weight > 0 }
        let total = cats.reduce(0) { $0 + $1.weight }
        guard total > 0 else {
            return GradeSummary(totalWeight: 0, currentPercent: nil, lockedInPoints: 0, gradedWeight: 0,
                                projectedPercent: nil, assumedCategoryIDs: [], bestCasePercent: nil, worstCasePercent: nil)
        }

        let graded = cats.map { ($0, percent(of: $0.gradedEntries, method: $0.method)) }
        let gradedOnly = graded.compactMap { cat, g in g.map { (cat, $0) } }
        let gradedWeight = gradedOnly.reduce(0) { $0 + $1.0.weight }
        let weightedGraded = gradedOnly.reduce(0) { $0 + $1.0.weight * $1.1 }
        let current: Double? = gradedWeight > 0 ? weightedGraded / gradedWeight : nil

        let withPlans = cats.map { ($0, percent(of: $0.entries, method: $0.method)) }
        let assumed = assumedValue(current: current, planned: withPlans)

        var projectedSum = 0.0
        var assumedIDs = Set<UUID>()
        var projectedPossible = assumed != nil || withPlans.allSatisfy({ $0.1 != nil })
        for (cat, p) in withPlans {
            if let p {
                projectedSum += cat.weight * p
            } else if let assumed {
                projectedSum += cat.weight * assumed
                assumedIDs.insert(cat.id)
            } else {
                projectedPossible = false
            }
        }

        let best = graded.reduce(0) { $0 + $1.0.weight * ($1.1 ?? 100) } / total
        let worst = graded.reduce(0) { $0 + $1.0.weight * ($1.1 ?? 0) } / total

        return GradeSummary(
            totalWeight: total,
            currentPercent: current,
            lockedInPoints: weightedGraded / total,
            gradedWeight: gradedWeight,
            projectedPercent: projectedPossible ? projectedSum / total : nil,
            assumedCategoryIDs: assumedIDs,
            bestCasePercent: best,
            worstCasePercent: worst
        )
    }

    /// The percent `categoryID` must reach for the final grade to hit `target`.
    public static func requiredPercent(target: Double, in categoryID: UUID,
                                       categories: [GradeCategoryInput]) -> RequiredScore {
        let cats = categories.filter { $0.weight > 0 }
        guard let chosen = cats.first(where: { $0.id == categoryID }) else { return .noWeight }
        let total = cats.reduce(0) { $0 + $1.weight }
        let graded = cats.compactMap { cat -> (GradeCategoryInput, Double)? in
            percent(of: cat.gradedEntries, method: cat.method).map { (cat, $0) }
        }
        let gradedWeight = graded.reduce(0) { $0 + $1.0.weight }
        let current: Double? = gradedWeight > 0 ? graded.reduce(0) { $0 + $1.0.weight * $1.1 } / gradedWeight : nil
        let withPlans = cats.map { ($0, percent(of: $0.entries, method: $0.method)) }
        let assumed = assumedValue(current: current, planned: withPlans)

        var others = 0.0
        for (cat, p) in withPlans where cat.id != chosen.id {
            guard let value = p ?? assumed else { return .noData }
            others += cat.weight * value
        }

        let needed = (target * total - others) / chosen.weight
        if needed <= 0 { return .secured }
        if needed > 100 { return .unreachable(maxPossible: (others + 100 * chosen.weight) / total) }
        return .needs(needed)
    }

    /// What to assume for a category with no entries: the grade so far, or the average of
    /// whatever is entered (graded or planned) when nothing is graded yet.
    private static func assumedValue(current: Double?, planned: [(GradeCategoryInput, Double?)]) -> Double? {
        if let current { return current }
        let known = planned.compactMap { cat, p in p.map { (cat.weight, $0) } }
        let weight = known.reduce(0) { $0 + $1.0 }
        guard weight > 0 else { return nil }
        return known.reduce(0) { $0 + $1.0 * $1.1 } / weight
    }
}

public struct CourseGPAInput: Sendable {
    public var credits: Double
    public var percent: Double?
    public var countsTowardGPA: Bool
    public var scale: GradeScale

    public init(credits: Double, percent: Double?, countsTowardGPA: Bool = true, scale: GradeScale) {
        self.credits = credits
        self.percent = percent
        self.countsTowardGPA = countsTowardGPA
        self.scale = scale
    }
}

public enum GPACalculator {
    /// Credit-weighted GPA over courses that count and have a grade. F (0 points) is included.
    public static func gpa(_ courses: [CourseGPAInput]) -> Double? {
        var points = 0.0
        var credits = 0.0
        for course in courses where course.countsTowardGPA && course.credits > 0 {
            guard let percent = course.percent, let band = course.scale.band(for: percent) else { continue }
            points += course.credits * band.gpaPoints
            credits += course.credits
        }
        return credits > 0 ? points / credits : nil
    }
}
