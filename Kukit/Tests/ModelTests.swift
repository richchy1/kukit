import Foundation
import SwiftData
import Testing
import KukitCore
@testable import Kukit

@MainActor
@Suite("Models")
struct ModelTests {
    func makeContext() throws -> ModelContext {
        ModelContext(try KukitSchema.makeContainer(inMemory: true))
    }

    @Test func seedingCreatesOneDefaultKoreanScale() throws {
        let context = try makeContext()
        GradingScales.seedIfNeeded(context)
        GradingScales.seedIfNeeded(context)   // second launch must not duplicate it
        let scales = try context.fetch(FetchDescriptor<GradingScale>())
        #expect(scales.count == 1)
        #expect(scales[0].isDefault)
        #expect(scales[0].scale == GradeScale.korean45.withSameBandIDs(as: scales[0].scale))
        #expect(scales[0].bands.count == 9)
        #expect(scales[0].scale.band(for: 95)?.label == "A+")
    }

    @Test func scaleBandsSurviveASaveAndFetch() throws {
        let context = try makeContext()
        var custom = GradeScale.korean45
        custom.name = "Mine"
        custom.rounding = .nearest
        custom.bands.append(GradeBand(minPercent: 99, label: "S", gpaPoints: 4.5))
        context.insert(GradingScale(custom))
        try context.save()
        let fetched = try #require(try context.fetch(FetchDescriptor<GradingScale>()).first)
        #expect(fetched.scale == custom)
        #expect(fetched.scale.band(for: 98.6)?.label == "S")     // 98.6 rounds to 99
    }

    @Test func courseGradeSummaryUsesItsCategoriesAndEntries() throws {
        let context = try makeContext()
        let course = Course(name: "Calculus")
        context.insert(course)
        func category(_ name: String, _ weight: Double, _ order: Int) -> GradeCategory {
            let c = GradeCategory(name: name, weight: weight, sortOrder: order, course: course)
            context.insert(c)
            return c
        }
        let hw = category("Homework", 20, 0), mid = category("Midterm", 30, 1)
        let part = category("Participation", 10, 2), final = category("Final", 40, 3)
        context.insert(GradeEntry(name: "HW", score: 90, maxScore: 100, category: hw))
        context.insert(GradeEntry(name: "Mid", score: 40, maxScore: 50, category: mid))
        context.insert(GradeEntry(name: "Part", score: 10, maxScore: 10, category: part))
        try context.save()

        #expect(course.sortedCategories.map(\.name) == ["Homework", "Midterm", "Participation", "Final"])
        let summary = course.gradeSummary
        #expect(abs((summary.currentPercent ?? 0) - 86.6667) < 0.001)
        #expect(abs(summary.lockedInPoints - 52) < 0.0001)

        let result = GradeCalculator.requiredPercent(target: 90, in: final.id, categories: course.categoryInputs)
        guard case .needs(let needed) = result else { Issue.record("expected .needs"); return }
        #expect(abs(needed - 95) < 0.0001)
    }

    @Test func deletingACourseRemovesItsCategoriesEntriesTasksAndSessions() throws {
        let context = try makeContext()
        let course = Course(name: "Physics")
        context.insert(course)
        let category = GradeCategory(name: "Final", weight: 100, course: course)
        context.insert(category)
        context.insert(GradeEntry(name: "Final", score: 80, maxScore: 100, category: category))
        context.insert(Assignment(title: "Lab 1", course: course))
        context.insert(StudySession(startedAt: .now, endedAt: .now, focusSeconds: 600,
                                    presetName: "Classic", kind: .pomodoro, course: course))
        try context.save()

        context.delete(course)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<GradeCategory>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<GradeEntry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Assignment>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<StudySession>()) == 0)
    }

    @Test func deletingAScaleSendsCoursesBackToTheDefault() throws {
        let context = try makeContext()
        let defaultScale = GradingScale(.korean45, isDefault: true)
        let other = GradingScale(GradeScale(name: "Other", gpaMax: 4, bands: [
            GradeBand(minPercent: 50, label: "P", gpaPoints: 4), GradeBand(minPercent: 0, label: "F", gpaPoints: 0)]))
        context.insert(defaultScale)
        context.insert(other)
        let course = Course(name: "Art")
        course.gradeScale = other
        context.insert(course)
        try context.save()
        #expect(GradingScales.resolve(for: course, in: [defaultScale, other]).name == "Other")

        context.delete(other)
        try context.save()
        #expect(course.gradeScale == nil)
        #expect(GradingScales.resolve(for: course, in: [defaultScale]).name == "Korean (4.5)")
    }

    @Test func assignmentStatusTracksCompletionAndBuckets() throws {
        let item = Assignment(title: "Essay", course: nil, dueDate: Calendar.current.startOfDay(for: .now))
        #expect(item.dueBucket == .today)
        #expect(!item.isDone && item.completedAt == nil)
        item.status = .done
        #expect(item.isDone && item.completedAt != nil)
        item.status = .todo
        #expect(item.completedAt == nil)

        let late = Assignment(title: "Old", course: nil,
                              dueDate: Calendar.current.date(byAdding: .day, value: -3, to: .now))
        #expect(late.isOverdue)
        late.status = .done
        #expect(!late.isOverdue)
    }

    @Test func reminderTaskMappingUsesDefaultsUnlessOverridden() throws {
        UserDefaults.standard.set("1440,120", forKey: Prefs.reminderOffsetsTask)
        UserDefaults.standard.set("4320,1440,120", forKey: Prefs.reminderOffsetsExam)
        let due = Date.now.addingTimeInterval(5 * 86_400)
        let homework = Assignment(title: "HW", course: Course(name: "Calc"), dueDate: due, hasDueTime: true)
        let exam = Assignment(title: "Midterm", course: Course(name: "Calc"), type: .exam, dueDate: due, hasDueTime: true)
        #expect(ReminderScheduler.task(from: homework)?.offsets == [1440, 120])
        #expect(ReminderScheduler.task(from: exam)?.offsets == [4320, 1440, 120])
        exam.customReminderOffsets = [60]
        #expect(ReminderScheduler.task(from: exam)?.offsets == [60])
        #expect(ReminderScheduler.task(from: Assignment(title: "No date", course: nil)) == nil)
    }

    @Test func gradeEntryLinkFollowsTheAssignment() throws {
        let context = try makeContext()
        let course = Course(name: "Bio")
        let category = GradeCategory(name: "Homework", weight: 100, course: course)
        let task = Assignment(title: "Quiz 1", course: course)
        let entry = GradeEntry(name: "Quiz 1", score: 8, maxScore: 10, isPlanned: true, category: category)
        context.insert(course); context.insert(category); context.insert(task); context.insert(entry)
        task.gradeEntry = entry
        try context.save()
        #expect(entry.assignment?.id == task.id)
        #expect(course.gradeSummary.currentPercent == nil)          // planned only

        entry.isPlanned = false
        #expect(abs((course.gradeSummary.currentPercent ?? 0) - 80) < 0.0001)

        context.delete(task)
        try context.save()
        #expect(entry.assignment == nil)                              // the score is kept
        #expect(try context.fetchCount(FetchDescriptor<GradeEntry>()) == 1)
    }

    @Test func customPresetBecomesAClampedTimerConfig() throws {
        let preset = TimerPreset(name: "Wild", focusMinutes: 999, shortBreakMinutes: 0,
                                 longBreakMinutes: 20, roundsBeforeLongBreak: 1)
        let config = preset.config
        #expect(config.focusMinutes == 240 && config.shortBreakMinutes == 1 && config.roundsBeforeLongBreak == 2)
        #expect(!config.isBuiltIn)
        #expect(config.id == preset.id.uuidString)
    }
}

private extension GradeScale {
    /// Band IDs are random per instance; align them so two scales compare by content only.
    func withSameBandIDs(as other: GradeScale) -> GradeScale {
        var copy = self
        copy.bands = zip(bands, other.bands).map { mine, theirs in
            GradeBand(id: theirs.id, minPercent: mine.minPercent, label: mine.label, gpaPoints: mine.gpaPoints)
        }
        return copy
    }
}
