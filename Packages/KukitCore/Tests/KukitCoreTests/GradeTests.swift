import Foundation
import Testing
@testable import KukitCore

private func near(_ value: Double?, _ expected: Double, tolerance: Double = 0.0001) -> Bool {
    guard let value else { return false }
    return abs(value - expected) < tolerance
}

@Suite("GradeScale")
struct GradeScaleTests {
    let scale = GradeScale.korean45

    @Test func boundariesFallIntoTheHigherBand() {
        #expect(scale.band(for: 95)?.label == "A+")
        #expect(scale.band(for: 94.99)?.label == "A0")
        #expect(scale.band(for: 90)?.label == "A0")
        #expect(scale.band(for: 89.99)?.label == "B+")
        #expect(scale.band(for: 60)?.label == "D0")
        #expect(scale.band(for: 59.99)?.label == "F")
        #expect(scale.band(for: 0)?.label == "F")
        #expect(scale.band(for: 100)?.label == "A+")
    }

    @Test func floatingPointNoiseDoesNotDemoteAGrade() {
        // 285 / 300 * 100 is 95.00000000000001 or 94.99999999999999 depending on the route taken
        let percent = 0.95 * 100 - 1e-13
        #expect(scale.band(for: percent)?.label == "A+")
        #expect(scale.band(for: 285.0 * 100 / 300.0)?.label == "A+")
    }

    @Test func roundingToNearestPercent() {
        var rounded = scale
        rounded.rounding = .nearest
        #expect(rounded.band(for: 94.6)?.label == "A+")     // rounds to 95
        #expect(scale.band(for: 94.6)?.label == "A0")        // exact: stays A0
        #expect(rounded.band(for: 94.4)?.label == "A0")
    }

    @Test func belowTheLowestBandOrNegativeHasNoBandWithoutAZeroBand() {
        var custom = scale
        custom.bands.removeAll { $0.minPercent == 0 }
        #expect(custom.band(for: 10) == nil)
        #expect(custom.issues().contains(.missingZeroBand))
    }

    @Test func defaultScaleIsValid() {
        #expect(scale.isValid)
        #expect(scale.gpaMax == 4.5)
        #expect(scale.bands.count == 9)
    }

    @Test func validationFindsProblems() {
        var bad = scale
        bad.bands.append(GradeBand(minPercent: 90, label: "", gpaPoints: 9))
        let issues = bad.issues()
        #expect(issues.contains(.duplicateThreshold(90)))
        #expect(issues.contains(.emptyLabel))
        #expect(issues.contains(.pointsOutOfRange(label: "")))
        #expect(GradeScale(name: "x", gpaMax: 4, bands: []).issues() == [.noBands])
        #expect(GradeScale(name: "x", gpaMax: 0, bands: scale.bands).issues().contains(.invalidGPAMax))
    }

    @Test func customScalesWork() {
        // A made-up 5-point system
        let five = GradeScale(name: "5-point", gpaMax: 5, bands: [
            GradeBand(minPercent: 90, label: "5", gpaPoints: 5),
            GradeBand(minPercent: 75, label: "4", gpaPoints: 4),
            GradeBand(minPercent: 0, label: "3", gpaPoints: 3),
        ])
        #expect(five.band(for: 80)?.label == "4")
        #expect(five.band(for: 10)?.gpaPoints == 3)
    }

    @Test func encodesAndDecodes() throws {
        let data = try JSONEncoder().encode(scale)
        #expect(try JSONDecoder().decode(GradeScale.self, from: data) == scale)
    }
}

@Suite("GradeCalculator")
struct GradeCalculatorTests {
    let hw = UUID(), mid = UUID(), final = UUID(), part = UUID()

    /// Homework 20 % (90), Midterm 30 % (80), Participation 10 % (100), Final 40 % (nothing yet)
    func example(finalEntries: [GradeEntryInput] = []) -> [GradeCategoryInput] {
        [
            GradeCategoryInput(id: hw, name: "Homework", weight: 20, entries: [GradeEntryInput(score: 90, maxScore: 100)]),
            GradeCategoryInput(id: mid, name: "Midterm", weight: 30, entries: [GradeEntryInput(score: 40, maxScore: 50)]),
            GradeCategoryInput(id: part, name: "Participation", weight: 10, entries: [GradeEntryInput(score: 10, maxScore: 10)]),
            GradeCategoryInput(id: final, name: "Final", weight: 40, entries: finalEntries),
        ]
    }

    @Test func workedExample() {
        let summary = GradeCalculator.summary(example())
        #expect(near(summary.currentPercent, 86.6667, tolerance: 0.001))
        #expect(near(summary.lockedInPoints, 52))
        #expect(near(summary.gradedWeight, 60))
        #expect(near(summary.totalWeight, 100))
        // Projection assumes the Final matches the current grade
        #expect(near(summary.projectedPercent, 86.6667, tolerance: 0.001))
        #expect(summary.assumedCategoryIDs == [final])
        #expect(near(summary.bestCasePercent, 92))
        #expect(near(summary.worstCasePercent, 52))
    }

    @Test func requiredScoreOnTheFinal() {
        let result = GradeCalculator.requiredPercent(target: 90, in: final, categories: example())
        guard case .needs(let needed) = result else { Issue.record("expected .needs, got \(result)"); return }
        #expect(near(needed, 95))
        let letterA = GradeScale.korean45.band(for: 95)?.minPercent
        #expect(letterA == 95)
    }

    @Test func requiredScoreStates() {
        // Already secured: 52 locked in, target 50 needs less than 0 on the Final
        #expect(GradeCalculator.requiredPercent(target: 50, in: final, categories: example()) == .secured)
        // Not reachable: 52 + 40 = 92 is the ceiling
        let result = GradeCalculator.requiredPercent(target: 95, in: final, categories: example())
        guard case .unreachable(let max) = result else { Issue.record("expected unreachable"); return }
        #expect(near(max, 92))
        // Exactly 100 % needed is still reachable
        guard case .needs(let exact) = GradeCalculator.requiredPercent(target: 92, in: final, categories: example()) else {
            Issue.record("expected needs"); return
        }
        #expect(near(exact, 100))
    }

    @Test func plannedEntriesFeedTheProjectionButNotTheCurrentGrade() {
        let planned = example(finalEntries: [GradeEntryInput(score: 95, maxScore: 100, isPlanned: true)])
        let summary = GradeCalculator.summary(planned)
        #expect(near(summary.currentPercent, 86.6667, tolerance: 0.001))
        #expect(near(summary.projectedPercent, 52 + 0.4 * 95))        // 90
        #expect(summary.assumedCategoryIDs.isEmpty)
        #expect(near(summary.worstCasePercent, 52))                   // planned doesn't count as graded
    }

    @Test func requiredScoreUsesPlannedValuesElsewhere() {
        var cats = example()
        // Remove the midterm result and plan 70 % for it instead
        cats[1].entries = [GradeEntryInput(score: 35, maxScore: 50, isPlanned: true)]
        let result = GradeCalculator.requiredPercent(target: 80, in: final, categories: cats)
        // others = 20*90 + 30*70 + 10*100 = 4900; (8000 - 4900)/40 = 77.5
        guard case .needs(let needed) = result else { Issue.record("expected needs"); return }
        #expect(near(needed, 77.5))
    }

    @Test func gradingFinishedCourse() {
        let cats = example(finalEntries: [GradeEntryInput(score: 95, maxScore: 100)])
        let summary = GradeCalculator.summary(cats)
        #expect(near(summary.currentPercent, 90))
        #expect(near(summary.projectedPercent, 90))
        #expect(near(summary.bestCasePercent, 90))
        #expect(near(summary.worstCasePercent, 90))
    }

    @Test func totalPointsVersusAverageOfPercentages() {
        let entries = [GradeEntryInput(score: 5, maxScore: 10), GradeEntryInput(score: 90, maxScore: 100)]
        #expect(near(GradeCalculator.percent(of: entries, method: .totalPoints), 95 * 100 / 110.0))   // 86.36
        #expect(near(GradeCalculator.percent(of: entries, method: .averageOfPercentages), 70))
    }

    @Test func entriesWithZeroMaxAreIgnored() {
        #expect(GradeCalculator.percent(of: [GradeEntryInput(score: 5, maxScore: 0)], method: .totalPoints) == nil)
        #expect(GradeCalculator.percent(of: [], method: .totalPoints) == nil)
        let mixed = [GradeEntryInput(score: 5, maxScore: 0), GradeEntryInput(score: 8, maxScore: 10)]
        #expect(near(GradeCalculator.percent(of: mixed, method: .totalPoints), 80))
    }

    @Test func weightsThatDontAddUpTo100AreNormalised() {
        let cats = [
            GradeCategoryInput(name: "A", weight: 30, entries: [GradeEntryInput(score: 80, maxScore: 100)]),
            GradeCategoryInput(name: "B", weight: 20, entries: [GradeEntryInput(score: 100, maxScore: 100)]),
        ]
        let summary = GradeCalculator.summary(cats)
        #expect(near(summary.totalWeight, 50))
        #expect(near(summary.currentPercent, 88))                       // (2400 + 2000) / 50
        #expect(near(summary.lockedInPoints, 88))
    }

    @Test func noDataProducesNoNumbers() {
        let empty = GradeCalculator.summary([GradeCategoryInput(name: "A", weight: 50, entries: []),
                                             GradeCategoryInput(name: "B", weight: 50, entries: [])])
        #expect(empty.currentPercent == nil)
        #expect(empty.projectedPercent == nil)
        #expect(near(empty.lockedInPoints, 0))
        let id = UUID()
        let result = GradeCalculator.requiredPercent(
            target: 90, in: id,
            categories: [GradeCategoryInput(id: id, name: "A", weight: 50, entries: []),
                         GradeCategoryInput(name: "B", weight: 50, entries: [])])
        #expect(result == .noData)
        #expect(GradeCalculator.summary([]).currentPercent == nil)
    }

    @Test func zeroWeightCategoryIsIgnored() {
        let id = UUID()
        let cats = [GradeCategoryInput(id: id, name: "Extra", weight: 0, entries: [])]
        #expect(GradeCalculator.requiredPercent(target: 90, in: id, categories: cats) == .noWeight)
    }
}

@Suite("GPACalculator")
struct GPACalculatorTests {
    let scale = GradeScale.korean45

    @Test func creditWeightedAverage() {
        let courses = [
            CourseGPAInput(credits: 3, percent: 96, scale: scale),   // A+ 4.5
            CourseGPAInput(credits: 3, percent: 82, scale: scale),   // B0 3.0
            CourseGPAInput(credits: 2, percent: 72, scale: scale),   // C0 2.0
        ]
        // (13.5 + 9 + 4) / 8
        #expect(near(GPACalculator.gpa(courses), 3.3125))
    }

    @Test func failingGradesStillCountButPassFailAndUngradedDoNot() {
        let courses = [
            CourseGPAInput(credits: 3, percent: 96, scale: scale),                          // 4.5
            CourseGPAInput(credits: 3, percent: 40, scale: scale),                          // F 0
            CourseGPAInput(credits: 2, percent: 99, countsTowardGPA: false, scale: scale),   // P/NP: skipped
            CourseGPAInput(credits: 4, percent: nil, scale: scale),                         // no grade yet: skipped
            CourseGPAInput(credits: 0, percent: 80, scale: scale),                          // zero credits: skipped
        ]
        #expect(near(GPACalculator.gpa(courses), 2.25))
    }

    @Test func eachCourseUsesItsOwnScale() {
        let four = GradeScale(name: "4.0", gpaMax: 4, bands: [
            GradeBand(minPercent: 90, label: "A", gpaPoints: 4),
            GradeBand(minPercent: 0, label: "B", gpaPoints: 3),
        ])
        let courses = [CourseGPAInput(credits: 1, percent: 95, scale: four),
                       CourseGPAInput(credits: 1, percent: 95, scale: scale)]
        #expect(near(GPACalculator.gpa(courses), 4.25))
    }

    @Test func noQualifyingCoursesMeansNoGPA() {
        #expect(GPACalculator.gpa([]) == nil)
        #expect(GPACalculator.gpa([CourseGPAInput(credits: 3, percent: nil, scale: scale)]) == nil)
    }
}
