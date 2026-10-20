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

    @Test func notesNestAndDeleteWithTheirSubpages() throws {
        let context = try makeContext()
        let root = Note(title: "Calculus")
        let child = Note(title: "Limits", parent: root)
        let grandchild = Note(title: "Epsilon-delta", parent: child)
        [root, child, grandchild].forEach { context.insert($0) }
        try context.save()

        #expect(root.childNotes?.map(\.title) == ["Limits"])
        #expect(grandchild.childNotes == nil)                   // a leaf, as OutlineGroup expects
        #expect(root.descendantCount == 2)

        context.delete(child)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Note>()) == 1)   // grandchild went with it
    }

    @Test func deletingACourseKeepsItsNotes() throws {
        let context = try makeContext()
        let course = Course(name: "History")
        let note = Note(title: "Cold War", course: course)
        context.insert(course); context.insert(note)
        try context.save()
        #expect(note.course?.id == course.id)

        context.delete(course)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Note>()) == 1)
        #expect(note.course == nil)
    }

    @Test func notesAndTasksLinkBothWays() throws {
        let context = try makeContext()
        let task = Assignment(title: "Essay", course: nil)
        let a = Note(title: "Outline"), b = Note(title: "Sources")
        [a, b].forEach { context.insert($0) }
        context.insert(task)
        a.assignments = [task]
        b.assignments = [task]
        try context.save()
        #expect(Set((task.notes ?? []).map(\.title)) == ["Outline", "Sources"])

        context.delete(a)
        try context.save()
        #expect((task.notes ?? []).map(\.title) == ["Sources"])
        #expect(try context.fetchCount(FetchDescriptor<Assignment>()) == 1)
    }

    @Test func templatesProduceUsableMarkdown() throws {
        let course = Course(name: "Physics")
        for template in NoteTemplate.allCases {
            let note = template.make(course: course, parent: nil)
            #expect(note.course === course)
            if template != .blank {
                #expect(!note.title.isEmpty)
                let blocks = Markdown.parse(note.markdownBody)
                #expect(blocks.contains { if case .heading = $0 { true } else { false } })
            }
        }
        let lecture = NoteTemplate.lecture.make(course: nil, parent: nil)
        let hasChecklist = Markdown.parse(lecture.markdownBody).contains {
            if case .list(_, let items) = $0 { items.contains { $0.checked != nil } } else { false }
        }
        #expect(hasChecklist)
        #expect(NoteTemplate.cheatSheet.make(course: course, parent: nil).title == "Physics cheat-sheet")
        #expect(Note(title: "  ").displayTitle == "Untitled")
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

@MainActor
@Suite("Backup")
struct BackupTests {
    func makeContext() throws -> ModelContext { ModelContext(try KukitSchema.makeContainer(inMemory: true)) }

    /// A small but fully connected data set exercising every relationship.
    func populate(_ context: ModelContext) throws -> (course: Course, task: Assignment, note: Note) {
        GradingScales.seedIfNeeded(context)
        let semester = Semester(name: "Fall 2026")
        let course = Course(name: "미적분학", code: "MATH201", credits: 3, semester: semester)
        course.targetPercent = 92
        let scale = GradingScale(GradeScale(name: "Mine", gpaMax: 4, bands: [
            GradeBand(minPercent: 50, label: "P", gpaPoints: 4), GradeBand(minPercent: 0, label: "F", gpaPoints: 0)]))
        course.gradeScale = scale
        let category = GradeCategory(name: "Final", weight: 100, course: course)
        let task = Assignment(title: "Problem set 5", course: course, type: .homework,
                              dueDate: Date(timeIntervalSince1970: 1_800_000_000), hasDueTime: true)
        task.customReminderOffsets = [60, 1440]
        let entry = GradeEntry(name: "Final", score: 88, maxScore: 100, isPlanned: false, category: category)
        entry.assignment = task
        let parent = Note(title: "Calculus", markdownBody: "# Limits\n- [ ] review", course: course)
        let child = Note(title: "Epsilon", markdownBody: "see [[Calculus]]", course: course, parent: parent)
        parent.isPinned = true
        parent.assignments = [task]
        let session = StudySession(startedAt: Date(timeIntervalSince1970: 1_790_000_000),
                                   endedAt: Date(timeIntervalSince1970: 1_790_001_500), focusSeconds: 1500,
                                   presetName: "Classic", kind: .pomodoro, comment: "limits", assignmentID: task.id, course: course)
        let preset = TimerPreset(name: "Night owl", focusMinutes: 40, shortBreakMinutes: 8, longBreakMinutes: 20,
                                 roundsBeforeLongBreak: 4, sortOrder: 1)
        for model in [semester, scale, course, category, task, entry, parent, child, session, preset] as [any PersistentModel] {
            context.insert(model)
        }
        try context.save()
        return (course, task, parent)
    }

    func counts(_ context: ModelContext) throws -> [Int] {
        [try context.fetchCount(FetchDescriptor<Course>()), try context.fetchCount(FetchDescriptor<Assignment>()),
         try context.fetchCount(FetchDescriptor<Note>()), try context.fetchCount(FetchDescriptor<StudySession>()),
         try context.fetchCount(FetchDescriptor<GradeCategory>()), try context.fetchCount(FetchDescriptor<GradeEntry>()),
         try context.fetchCount(FetchDescriptor<GradingScale>()), try context.fetchCount(FetchDescriptor<TimerPreset>()),
         try context.fetchCount(FetchDescriptor<Semester>())]
    }

    @Test func exportThenImportIntoAnEmptyStoreReproducesEverything() throws {
        let source = try makeContext()
        _ = try populate(source)
        let data = try BackupService.exportData(from: source)

        let target = try makeContext()
        let document = try BackupService.decode(data)
        try BackupService.restore(document, mode: .merge, into: target)

        #expect(try counts(target) == counts(source))
        let course = try #require(try target.fetch(FetchDescriptor<Course>()).first)
        #expect(course.name == "미적분학" && course.code == "MATH201" && course.targetPercent == 92)
        #expect(course.semester?.name == "Fall 2026")
        #expect(course.gradeScale?.name == "Mine")
        #expect(course.gradeScale?.bands.count == 2)
        #expect(course.gradeCategories?.count == 1)
        #expect(course.gradeSummary.currentPercent == 88)
        #expect((course.assignments ?? []).first?.customReminderOffsets == [60, 1440])
        #expect((course.assignments ?? []).first?.gradeEntry?.score == 88)       // task <-> score link survived

        let notes = try target.fetch(FetchDescriptor<Note>())
        let parent = try #require(notes.first { $0.title == "Calculus" })
        #expect(parent.isPinned && parent.course?.id == course.id)
        #expect(parent.childNotes?.map(\.title) == ["Epsilon"])
        #expect((parent.assignments ?? []).map(\.title) == ["Problem set 5"])
        let session = try #require(try target.fetch(FetchDescriptor<StudySession>()).first)
        #expect(session.course?.id == course.id && session.focusSeconds == 1500 && session.comment == "limits")
        #expect(session.assignmentID == (course.assignments ?? []).first?.id)
    }

    @Test func importingTheSameBackupTwiceDoesNotDuplicate() throws {
        let source = try makeContext()
        _ = try populate(source)
        let document = try BackupService.decode(try BackupService.exportData(from: source))
        let target = try makeContext()
        try BackupService.restore(document, mode: .merge, into: target)
        let once = try counts(target)
        let second = try BackupService.restore(document, mode: .merge, into: target)
        #expect(try counts(target) == once)
        #expect(second.totalNew == 0)
    }

    @Test func mergeAddsOnlyWhatIsMissingAndKeepsLocalChanges() throws {
        let source = try makeContext()
        let made = try populate(source)
        let document = try BackupService.decode(try BackupService.exportData(from: source))

        let target = try makeContext()
        try BackupService.restore(document, mode: .merge, into: target)
        // Local edits after the first import
        let localCourse = try #require(try target.fetch(FetchDescriptor<Course>()).first)
        localCourse.name = "Calculus (renamed here)"
        target.insert(Course(name: "Brand new local course"))
        try target.save()

        try BackupService.restore(document, mode: .merge, into: target)
        let names = Set(try target.fetch(FetchDescriptor<Course>()).map(\.name))
        #expect(names == ["Calculus (renamed here)", "Brand new local course"])
        _ = made
    }

    @Test func newerNotesInTheBackupUpdateAndOlderOnesDoNot() throws {
        let source = try makeContext()
        let made = try populate(source)
        made.note.markdownBody = "edited on the other device"
        made.note.updatedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let document = try BackupService.decode(try BackupService.exportData(from: source))

        let target = try makeContext()
        try BackupService.restore(document, mode: .merge, into: target)       // creates it
        let local = try #require(try target.fetch(FetchDescriptor<Note>()).first { $0.title == "Calculus" })
        #expect(local.markdownBody == "edited on the other device")

        local.markdownBody = "newer local edit"
        local.updatedAt = Date(timeIntervalSince1970: 2_100_000_000)
        try BackupService.restore(document, mode: .merge, into: target)
        #expect(local.markdownBody == "newer local edit")                      // backup is older: skipped

        local.updatedAt = Date(timeIntervalSince1970: 1_000_000_000)
        try BackupService.restore(document, mode: .merge, into: target)
        #expect(local.markdownBody == "edited on the other device")            // backup is newer: updated
    }

    @Test func replaceErasesFirst() throws {
        let source = try makeContext()
        _ = try populate(source)
        let document = try BackupService.decode(try BackupService.exportData(from: source))

        let target = try makeContext()
        target.insert(Course(name: "Will be erased"))
        target.insert(Note(title: "Also erased"))
        try target.save()
        try BackupService.restore(document, mode: .replace, into: target)

        #expect(try target.fetch(FetchDescriptor<Course>()).map(\.name) == ["미적분학"])
        #expect(try target.fetch(FetchDescriptor<Note>()).count == 2)
        #expect(try counts(target) == counts(source))
    }

    @Test func onlyOneDefaultGradingScaleSurvivesAMerge() throws {
        let source = try makeContext()
        _ = try populate(source)                                     // seeds a default Korean scale
        let document = try BackupService.decode(try BackupService.exportData(from: source))

        let target = try makeContext()
        GradingScales.seedIfNeeded(target)                           // this device already has its own default
        try BackupService.restore(document, mode: .merge, into: target)
        let scales = try target.fetch(FetchDescriptor<GradingScale>())
        #expect(scales.filter(\.isDefault).count == 1)
        #expect(scales.count == 3)                                   // local default + backup's default + "Mine"
    }

    @Test func badFilesAreRejectedWithClearErrors() throws {
        #expect(throws: BackupError.notABackup) { try BackupService.decode(Data("hello".utf8)) }
        #expect(throws: BackupError.notABackup) { try BackupService.decode(Data("{\"app\":\"Other\",\"version\":1}".utf8)) }
        #expect(throws: BackupError.newerVersion(99)) { try BackupService.decode(Data("{\"app\":\"Kukit\",\"version\":99}".utf8)) }
        #expect(throws: BackupError.unreadable) { try BackupService.decode(Data("{\"app\":\"Kukit\",\"version\":1,\"courses\":5}".utf8)) }
    }

    @Test func eraseAllLeavesAFreshInstall() throws {
        let context = try makeContext()
        _ = try populate(context)
        try BackupService.eraseAll(context)
        #expect(try context.fetchCount(FetchDescriptor<Course>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Note>()) == 0)
        let scales = try context.fetch(FetchDescriptor<GradingScale>())
        #expect(scales.count == 1 && scales[0].isDefault)            // the Korean default is back
    }

    @Test func csvExportsHaveHeadersAndQuoteCommas() throws {
        let context = try makeContext()
        let made = try populate(context)
        made.course.name = "Art, history"
        try context.save()
        let sessions = try BackupService.sessionsCSV(from: context)
        #expect(sessions.hasPrefix("\u{FEFF}Started,Course,Technique,Minutes,Note\r\n"))
        #expect(sessions.contains("\"Art, history\",Classic,25.0,limits"))
        let grades = try BackupService.gradesCSV(from: context)
        #expect(grades.contains("\"Art, history\",Final,100,Final,88,100,88.00,graded,"))
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
