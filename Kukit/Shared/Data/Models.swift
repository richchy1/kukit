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
        Semester.self, Course.self, StudySession.self, TimerPreset.self,
    ]

    @MainActor
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        // cloudKitDatabase: .none keeps data local until sync is deliberately enabled.
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
