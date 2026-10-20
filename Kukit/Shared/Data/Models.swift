import Foundation
import SwiftData
import KukitCore

// All models follow CloudKit-compatible rules (defaults on every property, optional
// relationships, no unique constraints) so iCloud sync can be switched on later
// without reshaping the data. See docs/SPEC.md §7.1.

@Model
final class Semester {
    var id: UUID = UUID()
    var name: String = ""
    var startDate: Date = Date.now
    var endDate: Date?

    @Relationship(deleteRule: .nullify, inverse: \Course.semester)
    var courses: [Course]?

    init(name: String, startDate: Date = .now, endDate: Date? = nil) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
    }
}

@Model
final class Course {
    var id: UUID = UUID()
    var name: String = ""
    var code: String = ""
    var credits: Double = 3
    var colorHex: String = CoursePalette.colors[0].hex
    var symbolName: String = "book.closed"
    var instructor: String = ""
    var isArchived: Bool = false
    var countsTowardGPA: Bool = true
    var createdAt: Date = Date.now

    var semester: Semester?

    @Relationship(deleteRule: .cascade, inverse: \StudySession.course)
    var sessions: [StudySession]?

    @Relationship(deleteRule: .cascade, inverse: \Assignment.course)
    var assignments: [Assignment]?

    /// nil means "use the default grading scale".
    var gradeScale: GradingScale?
    var targetPercent: Double = 90

    @Relationship(deleteRule: .cascade, inverse: \GradeCategory.course)
    var gradeCategories: [GradeCategory]?

    /// Notes survive a course being deleted (they simply become unfiled).
    @Relationship(deleteRule: .nullify, inverse: \Note.course)
    var notes: [Note]?

    init(name: String, code: String = "", credits: Double = 3,
         colorHex: String = CoursePalette.colors[0].hex, symbolName: String = "book.closed",
         instructor: String = "", semester: Semester? = nil) {
        self.name = name
        self.code = code
        self.credits = credits
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.instructor = instructor
        self.semester = semester
    }
}

@Model
final class StudySession {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    var endedAt: Date = Date.now
    var focusSeconds: Double = 0
    var presetName: String = ""
    var kindRaw: String = TimerKind.pomodoro.rawValue
    var comment: String = ""
    /// Reserved for assignments (v0.2); stored as an ID until that model exists.
    var assignmentID: UUID?

    var course: Course?

    init(startedAt: Date, endedAt: Date, focusSeconds: Double, presetName: String,
         kind: TimerKind, comment: String = "", assignmentID: UUID? = nil, course: Course?) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.focusSeconds = focusSeconds
        self.presetName = presetName
        self.kindRaw = kind.rawValue
        self.comment = comment
        self.assignmentID = assignmentID
        self.course = course
    }

    var kind: TimerKind { TimerKind(rawValue: kindRaw) ?? .pomodoro }
    var summary: SessionSummary {
        SessionSummary(startedAt: startedAt, seconds: focusSeconds, courseID: course?.id)
    }
}

enum AssignmentType: String, CaseIterable, Identifiable, Sendable {
    case homework, quiz, project, lab, exam, reading, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .homework: "Homework"
        case .quiz: "Quiz"
        case .project: "Project"
        case .lab: "Lab"
        case .exam: "Exam"
        case .reading: "Reading"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .homework: "pencil.and.list.clipboard"
        case .quiz: "questionmark.circle"
        case .project: "hammer"
        case .lab: "flask"
        case .exam: "graduationcap"
        case .reading: "book"
        case .other: "tray"
        }
    }
}

enum AssignmentPriority: Int, CaseIterable, Identifiable, Sendable {
    case low = 0, normal = 1, high = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }
}

enum AssignmentStatus: String, CaseIterable, Identifiable, Sendable {
    case todo, inProgress, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "To do"
        case .inProgress: "In progress"
        case .done: "Done"
        }
    }
}

@Model
final class Assignment {
    var id: UUID = UUID()
    var title: String = ""
    var typeRaw: String = AssignmentType.homework.rawValue
    /// For date-only tasks this is the start of the due day.
    var dueDate: Date?
    var hasDueTime: Bool = false
    var priorityRaw: Int = AssignmentPriority.normal.rawValue
    var statusRaw: String = AssignmentStatus.todo.rawValue
    var details: String = ""
    var remindersEnabled: Bool = true
    /// Minutes before the due moment; nil means "use the defaults from Settings".
    var customReminderOffsets: [Int]?
    var completedAt: Date?
    var createdAt: Date = Date.now
    /// Synced flag; the EventKit identifier itself is kept per device (see EventKitService).
    var addedToAppleReminders: Bool = false
    var addedToCalendar: Bool = false

    var course: Course?
    var gradeEntry: GradeEntry?

    @Relationship(deleteRule: .nullify, inverse: \Note.assignments)
    var notes: [Note]?

    init(title: String, course: Course?, type: AssignmentType = .homework,
         dueDate: Date? = nil, hasDueTime: Bool = false) {
        self.title = title
        self.course = course
        self.typeRaw = type.rawValue
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
    }

    var type: AssignmentType {
        get { AssignmentType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var priority: AssignmentPriority {
        get { AssignmentPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var status: AssignmentStatus {
        get { AssignmentStatus(rawValue: statusRaw) ?? .todo }
        set {
            statusRaw = newValue.rawValue
            completedAt = newValue == .done ? (completedAt ?? .now) : nil
        }
    }

    var isDone: Bool { status == .done }
}

/// A user-defined timer technique. Built-in presets (Classic, Deep Work, Stopwatch) live in
/// code as `TimerConfig` values, so they never appear here or get duplicated by sync.
@Model
final class TimerPreset {
    var id: UUID = UUID()
    var name: String = ""
    var focusMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    var roundsBeforeLongBreak: Int = 4
    var sortOrder: Int = 0
    var createdAt: Date = Date.now

    init(name: String, focusMinutes: Int = 25, shortBreakMinutes: Int = 5,
         longBreakMinutes: Int = 15, roundsBeforeLongBreak: Int = 4, sortOrder: Int = 0) {
        self.name = name
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.roundsBeforeLongBreak = roundsBeforeLongBreak
        self.sortOrder = sortOrder
    }

    var config: TimerConfig {
        TimerConfig(
            id: id.uuidString, name: name, kind: .pomodoro,
            focusMinutes: focusMinutes, shortBreakMinutes: shortBreakMinutes,
            longBreakMinutes: longBreakMinutes, roundsBeforeLongBreak: roundsBeforeLongBreak,
            isBuiltIn: false
        ).clamped()
    }
}

enum KukitSchema {
    static let models: [any PersistentModel.Type] = [
        Semester.self, Course.self, StudySession.self, TimerPreset.self, Assignment.self,
        GradingScale.self, GradeCategory.self, GradeEntry.self, Note.self,
    ]

    @MainActor
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        // cloudKitDatabase: .none keeps data local until sync is deliberately enabled.
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
