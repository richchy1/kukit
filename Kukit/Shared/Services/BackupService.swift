import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import KukitCore

// MARK: - File format

/// The backup file: plain JSON, every record keyed by its UUID, relationships stored as IDs.
/// Unknown fields from newer versions are ignored on import; `version` guards breaking changes.
struct BackupDocument: Codable {
    static let currentVersion = 1

    var app = "Kukit"
    var version = BackupDocument.currentVersion
    var exportedAt: Date
    var semesters: [SemesterDTO] = []
    var gradingScales: [GradingScaleDTO] = []
    var courses: [CourseDTO] = []
    var gradeCategories: [GradeCategoryDTO] = []
    var assignments: [AssignmentDTO] = []
    var gradeEntries: [GradeEntryDTO] = []
    var notes: [NoteDTO] = []
    var sessions: [SessionDTO] = []
    var presets: [PresetDTO] = []
    var preferences: PreferencesDTO?

    struct SemesterDTO: Codable {
        var id: UUID
        var name: String
        var startDate: Date
        var endDate: Date?
    }

    struct GradingScaleDTO: Codable {
        var id: UUID
        var name: String
        var gpaMax: Double
        var rounding: String
        var isDefault: Bool
        var createdAt: Date
        var bands: [GradeBand]
    }

    struct CourseDTO: Codable {
        var id: UUID
        var name: String
        var code: String
        var credits: Double
        var colorHex: String
        var symbolName: String
        var instructor: String
        var isArchived: Bool
        var countsTowardGPA: Bool
        var createdAt: Date
        var targetPercent: Double
        var semesterID: UUID?
        var gradeScaleID: UUID?
    }

    struct GradeCategoryDTO: Codable {
        var id: UUID
        var name: String
        var weight: Double
        var method: String
        var sortOrder: Int
        var courseID: UUID?
    }

    struct AssignmentDTO: Codable {
        var id: UUID
        var title: String
        var type: String
        var dueDate: Date?
        var hasDueTime: Bool
        var priority: Int
        var status: String
        var details: String
        var remindersEnabled: Bool
        var customReminderOffsets: [Int]?
        var completedAt: Date?
        var createdAt: Date
        var addedToAppleReminders: Bool
        var addedToCalendar: Bool
        var courseID: UUID?
    }

    struct GradeEntryDTO: Codable {
        var id: UUID
        var name: String
        var score: Double
        var maxScore: Double
        var isPlanned: Bool
        var date: Date
        var categoryID: UUID?
        var assignmentID: UUID?
    }

    struct NoteDTO: Codable {
        var id: UUID
        var title: String
        var markdownBody: String
        var createdAt: Date
        var updatedAt: Date
        var isPinned: Bool
        var parentID: UUID?
        var courseID: UUID?
        var assignmentIDs: [UUID]
    }

    struct SessionDTO: Codable {
        var id: UUID
        var startedAt: Date
        var endedAt: Date
        var focusSeconds: Double
        var presetName: String
        var kind: String
        var comment: String
        var assignmentID: UUID?
        var courseID: UUID?
    }

    struct PresetDTO: Codable {
        var id: UUID
        var name: String
        var focusMinutes: Int
        var shortBreakMinutes: Int
        var longBreakMinutes: Int
        var roundsBeforeLongBreak: Int
        var sortOrder: Int
        var createdAt: Date
    }

    struct PreferencesDTO: Codable {
        var dailyGoalMinutes: Int
        var autoStartNext: Bool
        var minimumSessionMinutes: Int
        var reminderOffsetsTask: String
        var reminderOffsetsExam: String
        var allDayReminderHour: Int
    }
}

enum BackupError: LocalizedError, Equatable {
    case notABackup
    case newerVersion(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notABackup: "This file isn't a Kukit backup."
        case .newerVersion(let v): "This backup was made by a newer version of Kukit (format \(v)). Update the app to import it."
        case .unreadable: "The backup file is damaged or incomplete."
        }
    }
}

enum ImportMode: Equatable {
    /// Add what's missing; update notes the backup has newer edits for. Nothing is deleted.
    case merge
    /// Erase everything first, then load the backup.
    case replace
}

struct BackupPreview: Equatable {
    struct Line: Equatable, Identifiable {
        var name: String
        var total: Int
        var new: Int
        var id: String { name }
    }
    var exportedAt: Date
    var version: Int
    var lines: [Line]

    var totalNew: Int { lines.reduce(0) { $0 + $1.new } }
    var totalRecords: Int { lines.reduce(0) { $0 + $1.total } }
}

// MARK: - Service

@MainActor
enum BackupService {
    // MARK: Export

    static func makeDocument(from context: ModelContext, now: Date = .now) throws -> BackupDocument {
        var doc = BackupDocument(exportedAt: now)
        doc.semesters = try context.fetch(FetchDescriptor<Semester>()).map {
            .init(id: $0.id, name: $0.name, startDate: $0.startDate, endDate: $0.endDate)
        }
        doc.gradingScales = try context.fetch(FetchDescriptor<GradingScale>()).map {
            .init(id: $0.id, name: $0.name, gpaMax: $0.gpaMax, rounding: $0.roundingRaw,
                  isDefault: $0.isDefault, createdAt: $0.createdAt, bands: $0.bands)
        }
        doc.courses = try context.fetch(FetchDescriptor<Course>()).map {
            .init(id: $0.id, name: $0.name, code: $0.code, credits: $0.credits, colorHex: $0.colorHex,
                  symbolName: $0.symbolName, instructor: $0.instructor, isArchived: $0.isArchived,
                  countsTowardGPA: $0.countsTowardGPA, createdAt: $0.createdAt, targetPercent: $0.targetPercent,
                  semesterID: $0.semester?.id, gradeScaleID: $0.gradeScale?.id)
        }
        doc.gradeCategories = try context.fetch(FetchDescriptor<GradeCategory>()).map {
            .init(id: $0.id, name: $0.name, weight: $0.weight, method: $0.methodRaw,
                  sortOrder: $0.sortOrder, courseID: $0.course?.id)
        }
        doc.assignments = try context.fetch(FetchDescriptor<Assignment>()).map {
            .init(id: $0.id, title: $0.title, type: $0.typeRaw, dueDate: $0.dueDate, hasDueTime: $0.hasDueTime,
                  priority: $0.priorityRaw, status: $0.statusRaw, details: $0.details,
                  remindersEnabled: $0.remindersEnabled, customReminderOffsets: $0.customReminderOffsets,
                  completedAt: $0.completedAt, createdAt: $0.createdAt,
                  addedToAppleReminders: $0.addedToAppleReminders, addedToCalendar: $0.addedToCalendar,
                  courseID: $0.course?.id)
        }
        doc.gradeEntries = try context.fetch(FetchDescriptor<GradeEntry>()).map {
            .init(id: $0.id, name: $0.name, score: $0.score, maxScore: $0.maxScore, isPlanned: $0.isPlanned,
                  date: $0.date, categoryID: $0.category?.id, assignmentID: $0.assignment?.id)
        }
        doc.notes = try context.fetch(FetchDescriptor<Note>()).map {
            .init(id: $0.id, title: $0.title, markdownBody: $0.markdownBody, createdAt: $0.createdAt,
                  updatedAt: $0.updatedAt, isPinned: $0.isPinned, parentID: $0.parent?.id,
                  courseID: $0.course?.id, assignmentIDs: ($0.assignments ?? []).map(\.id))
        }
        doc.sessions = try context.fetch(FetchDescriptor<StudySession>()).map {
            .init(id: $0.id, startedAt: $0.startedAt, endedAt: $0.endedAt, focusSeconds: $0.focusSeconds,
                  presetName: $0.presetName, kind: $0.kindRaw, comment: $0.comment,
                  assignmentID: $0.assignmentID, courseID: $0.course?.id)
        }
        doc.presets = try context.fetch(FetchDescriptor<TimerPreset>()).map {
            .init(id: $0.id, name: $0.name, focusMinutes: $0.focusMinutes, shortBreakMinutes: $0.shortBreakMinutes,
                  longBreakMinutes: $0.longBreakMinutes, roundsBeforeLongBreak: $0.roundsBeforeLongBreak,
                  sortOrder: $0.sortOrder, createdAt: $0.createdAt)
        }
        let defaults = UserDefaults.standard
        doc.preferences = .init(
            dailyGoalMinutes: defaults.integer(forKey: Prefs.dailyGoalMinutes),
            autoStartNext: defaults.bool(forKey: Prefs.autoStartNext),
            minimumSessionMinutes: defaults.integer(forKey: Prefs.minimumSessionMinutes),
            reminderOffsetsTask: defaults.string(forKey: Prefs.reminderOffsetsTask) ?? "1440,120",
            reminderOffsetsExam: defaults.string(forKey: Prefs.reminderOffsetsExam) ?? "4320,1440,120",
            allDayReminderHour: ReminderDefaults.allDayHour
        )
        return doc
    }

    static func exportData(from context: ModelContext, now: Date = .now) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(makeDocument(from: context, now: now))
    }

    static func suggestedFilename(now: Date = .now) -> String {
        "kukit-backup-\(now.formatted(.iso8601.year().month().day()))"
    }

    // MARK: Import

    static func decode(_ data: Data) throws -> BackupDocument {
        struct Header: Decodable { var app: String?; var version: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              header.app == "Kukit", let version = header.version else { throw BackupError.notABackup }
        guard version <= BackupDocument.currentVersion else { throw BackupError.newerVersion(version) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(BackupDocument.self, from: data)
        } catch {
            throw BackupError.unreadable
        }
    }

    /// What importing would do, without changing anything.
    static func preview(_ document: BackupDocument, in context: ModelContext) throws -> BackupPreview {
        func line<M: PersistentModel>(_ name: String, _ ids: [UUID], _ type: M.Type, _ key: (M) -> UUID) throws -> BackupPreview.Line {
            let existing = Set(try context.fetch(FetchDescriptor<M>()).map(key))
            return .init(name: name, total: ids.count, new: ids.filter { !existing.contains($0) }.count)
        }
        let lines: [BackupPreview.Line] = [
            try line("Courses", document.courses.map(\.id), Course.self, { $0.id }),
            try line("Study sessions", document.sessions.map(\.id), StudySession.self, { $0.id }),
            try line("Tasks", document.assignments.map(\.id), Assignment.self, { $0.id }),
            try line("Notes", document.notes.map(\.id), Note.self, { $0.id }),
            try line("Grade categories", document.gradeCategories.map(\.id), GradeCategory.self, { $0.id }),
            try line("Scores", document.gradeEntries.map(\.id), GradeEntry.self, { $0.id }),
            try line("Grading scales", document.gradingScales.map(\.id), GradingScale.self, { $0.id }),
            try line("Techniques", document.presets.map(\.id), TimerPreset.self, { $0.id }),
            try line("Semesters", document.semesters.map(\.id), Semester.self, { $0.id }),
        ].filter { $0.total > 0 }
        return BackupPreview(exportedAt: document.exportedAt, version: document.version, lines: lines)
    }

    @discardableResult
    static func restore(_ doc: BackupDocument, mode: ImportMode, into context: ModelContext) throws -> BackupPreview {
        var result = try preview(doc, in: context)
        if mode == .replace {
            result.lines = result.lines.map { .init(name: $0.name, total: $0.total, new: $0.total) }
            try wipe(context)
        }

        // Index what already exists (empty after a wipe).
        var semesters = index(try context.fetch(FetchDescriptor<Semester>())) { $0.id }
        var scales = index(try context.fetch(FetchDescriptor<GradingScale>())) { $0.id }
        var courses = index(try context.fetch(FetchDescriptor<Course>())) { $0.id }
        var categories = index(try context.fetch(FetchDescriptor<GradeCategory>())) { $0.id }
        var assignments = index(try context.fetch(FetchDescriptor<Assignment>())) { $0.id }
        var entries = index(try context.fetch(FetchDescriptor<GradeEntry>())) { $0.id }
        var notes = index(try context.fetch(FetchDescriptor<Note>())) { $0.id }
        let sessions = index(try context.fetch(FetchDescriptor<StudySession>())) { $0.id }
        let presets = index(try context.fetch(FetchDescriptor<TimerPreset>())) { $0.id }

        let hasDefaultScale = scales.values.contains { $0.isDefault }

        // Create anything missing.
        for dto in doc.semesters where semesters[dto.id] == nil {
            let model = Semester(name: dto.name, startDate: dto.startDate, endDate: dto.endDate)
            model.id = dto.id
            context.insert(model)
            semesters[dto.id] = model
        }

        for dto in doc.gradingScales where scales[dto.id] == nil {
            let model = GradingScale(GradeScale(name: dto.name, gpaMax: dto.gpaMax,
                                                rounding: PercentRounding(rawValue: dto.rounding) ?? .none,
                                                bands: dto.bands))
            model.id = dto.id
            model.createdAt = dto.createdAt
            model.isDefault = dto.isDefault && !hasDefaultScale      // keep a single default
            context.insert(model)
            scales[dto.id] = model
        }

        var newCourses: [(Course, BackupDocument.CourseDTO)] = []
        for dto in doc.courses where courses[dto.id] == nil {
            let model = Course(name: dto.name, code: dto.code, credits: dto.credits, colorHex: dto.colorHex,
                               symbolName: dto.symbolName, instructor: dto.instructor)
            model.id = dto.id
            model.isArchived = dto.isArchived
            model.countsTowardGPA = dto.countsTowardGPA
            model.createdAt = dto.createdAt
            model.targetPercent = dto.targetPercent
            context.insert(model)
            courses[dto.id] = model
            newCourses.append((model, dto))
        }

        var newCategories: [(GradeCategory, BackupDocument.GradeCategoryDTO)] = []
        for dto in doc.gradeCategories where categories[dto.id] == nil {
            let model = GradeCategory(name: dto.name, weight: dto.weight, sortOrder: dto.sortOrder, course: nil)
            model.id = dto.id
            model.methodRaw = dto.method
            context.insert(model)
            categories[dto.id] = model
            newCategories.append((model, dto))
        }

        var newAssignments: [(Assignment, BackupDocument.AssignmentDTO)] = []
        for dto in doc.assignments where assignments[dto.id] == nil {
            let model = Assignment(title: dto.title, course: nil)
            model.id = dto.id
            model.typeRaw = dto.type
            model.dueDate = dto.dueDate
            model.hasDueTime = dto.hasDueTime
            model.priorityRaw = dto.priority
            model.statusRaw = dto.status
            model.details = dto.details
            model.remindersEnabled = dto.remindersEnabled
            model.customReminderOffsets = dto.customReminderOffsets
            model.completedAt = dto.completedAt
            model.createdAt = dto.createdAt
            model.addedToAppleReminders = dto.addedToAppleReminders
            model.addedToCalendar = dto.addedToCalendar
            context.insert(model)
            assignments[dto.id] = model
            newAssignments.append((model, dto))
        }

        var newEntries: [(GradeEntry, BackupDocument.GradeEntryDTO)] = []
        for dto in doc.gradeEntries where entries[dto.id] == nil {
            let model = GradeEntry(name: dto.name, score: dto.score, maxScore: dto.maxScore,
                                   isPlanned: dto.isPlanned, date: dto.date, category: nil)
            model.id = dto.id
            context.insert(model)
            entries[dto.id] = model
            newEntries.append((model, dto))
        }

        var linkedNotes: [(Note, BackupDocument.NoteDTO)] = []
        for dto in doc.notes {
            if let existing = notes[dto.id] {
                // Only notes carry an edit time, so only notes can be "updated if newer".
                guard dto.updatedAt > existing.updatedAt else { continue }
                existing.title = dto.title
                existing.markdownBody = dto.markdownBody
                existing.isPinned = dto.isPinned
                existing.updatedAt = dto.updatedAt
                linkedNotes.append((existing, dto))
            } else {
                let model = Note(title: dto.title, markdownBody: dto.markdownBody)
                model.id = dto.id
                model.createdAt = dto.createdAt
                model.updatedAt = dto.updatedAt
                model.isPinned = dto.isPinned
                context.insert(model)
                notes[dto.id] = model
                linkedNotes.append((model, dto))
            }
        }

        for dto in doc.sessions where sessions[dto.id] == nil {
            let model = StudySession(
                startedAt: dto.startedAt, endedAt: dto.endedAt, focusSeconds: dto.focusSeconds,
                presetName: dto.presetName, kind: TimerKind(rawValue: dto.kind) ?? .pomodoro,
                comment: dto.comment, assignmentID: dto.assignmentID, course: dto.courseID.flatMap { courses[$0] }
            )
            model.id = dto.id
            context.insert(model)
        }

        for dto in doc.presets where presets[dto.id] == nil {
            let model = TimerPreset(name: dto.name, focusMinutes: dto.focusMinutes,
                                    shortBreakMinutes: dto.shortBreakMinutes, longBreakMinutes: dto.longBreakMinutes,
                                    roundsBeforeLongBreak: dto.roundsBeforeLongBreak, sortOrder: dto.sortOrder)
            model.id = dto.id
            model.createdAt = dto.createdAt
            context.insert(model)
        }

        // Wire relationships for the records that were just created (or updated).
        for (model, dto) in newCourses {
            model.semester = dto.semesterID.flatMap { semesters[$0] }
            model.gradeScale = dto.gradeScaleID.flatMap { scales[$0] }
        }
        for (model, dto) in newCategories { model.course = dto.courseID.flatMap { courses[$0] } }
        for (model, dto) in newAssignments { model.course = dto.courseID.flatMap { courses[$0] } }
        for (model, dto) in newEntries {
            model.category = dto.categoryID.flatMap { categories[$0] }
            model.assignment = dto.assignmentID.flatMap { assignments[$0] }
        }
        for (model, dto) in linkedNotes {
            model.parent = dto.parentID.flatMap { notes[$0] }
            model.course = dto.courseID.flatMap { courses[$0] }
            model.assignments = dto.assignmentIDs.compactMap { assignments[$0] }
        }

        if mode == .replace, let prefs = doc.preferences { apply(prefs) }
        try context.save()
        if mode == .replace { GradingScales.seedIfNeeded(context) }
        return result
    }

    // MARK: Erase

    static func wipe(_ context: ModelContext) throws {
        try context.delete(model: StudySession.self)
        try context.delete(model: GradeEntry.self)
        try context.delete(model: GradeCategory.self)
        try context.delete(model: Assignment.self)
        try context.delete(model: Note.self)
        try context.delete(model: Course.self)
        try context.delete(model: Semester.self)
        try context.delete(model: GradingScale.self)
        try context.delete(model: TimerPreset.self)
        try context.save()
    }

    /// Erase everything and return to a fresh install (the default grading scale comes back).
    static func eraseAll(_ context: ModelContext) throws {
        try wipe(context)
        GradingScales.seedIfNeeded(context)
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Prefs.timerState)
        defaults.removeObject(forKey: Prefs.lastCourseID)
    }

    // MARK: CSV

    static func sessionsCSV(from context: ModelContext) throws -> String {
        let sessions = try context.fetch(FetchDescriptor<StudySession>(sortBy: [SortDescriptor(\.startedAt)]))
        let iso = Date.ISO8601FormatStyle()
        let rows = sessions.map { s in
            [s.startedAt.formatted(iso), s.course?.name ?? "", s.presetName,
             String(format: "%.1f", s.focusSeconds / 60), s.comment]
        }
        return CSV.document(header: ["Started", "Course", "Technique", "Minutes", "Note"], rows: rows)
    }

    static func gradesCSV(from context: ModelContext) throws -> String {
        let courses = try context.fetch(FetchDescriptor<Course>(sortBy: [SortDescriptor(\.name)]))
        var rows: [[String]] = []
        for course in courses {
            for category in course.sortedCategories {
                for entry in (category.entries ?? []).sorted(by: { $0.date < $1.date }) {
                    rows.append([
                        course.name, category.name, GradeFormat.number(category.weight), entry.name,
                        GradeFormat.number(entry.score), GradeFormat.number(entry.maxScore),
                        entry.percent.map { String(format: "%.2f", $0) } ?? "",
                        entry.isPlanned ? "planned" : "graded",
                        entry.date.formatted(.iso8601.year().month().day()),
                    ])
                }
            }
        }
        return CSV.document(
            header: ["Course", "Category", "Weight %", "Entry", "Score", "Max", "Percent", "Status", "Date"],
            rows: rows
        )
    }

    // MARK: Helpers

    private static func index<M>(_ models: [M], _ key: (M) -> UUID) -> [UUID: M] {
        Dictionary(models.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func apply(_ prefs: BackupDocument.PreferencesDTO) {
        let defaults = UserDefaults.standard
        defaults.set(prefs.dailyGoalMinutes, forKey: Prefs.dailyGoalMinutes)
        defaults.set(prefs.autoStartNext, forKey: Prefs.autoStartNext)
        defaults.set(prefs.minimumSessionMinutes, forKey: Prefs.minimumSessionMinutes)
        defaults.set(prefs.reminderOffsetsTask, forKey: Prefs.reminderOffsetsTask)
        defaults.set(prefs.reminderOffsetsExam, forKey: Prefs.reminderOffsetsExam)
        defaults.set(prefs.allDayReminderHour, forKey: Prefs.allDayReminderHour)
    }
}

// MARK: - File documents for the import/export panels

struct BackupFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    static let writableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct CSVFile: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]
    static let writableContentTypes: [UTType] = [.commaSeparatedText]
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        text = String(decoding: contents, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
