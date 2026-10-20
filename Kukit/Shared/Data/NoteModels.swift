import Foundation
import SwiftData
import KukitCore

/// A Markdown page. Pages can nest (subpages), belong to a course, and link to tasks.
@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    var markdownBody: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var isPinned: Bool = false

    var parent: Note?

    @Relationship(deleteRule: .cascade, inverse: \Note.parent)
    var children: [Note]?

    var course: Course?

    /// Tasks this page relates to (many-to-many; the inverse lives on `Assignment.notes`).
    var assignments: [Assignment]?

    init(title: String = "", markdownBody: String = "", course: Course? = nil, parent: Note? = nil) {
        self.title = title
        self.markdownBody = markdownBody
        self.course = course
        self.parent = parent
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// `nil` for pages without subpages (what `List(children:)` / `OutlineGroup` expect for a leaf).
    var childNotes: [Note]? {
        guard let children, !children.isEmpty else { return nil }
        return children.sorted { $0.createdAt < $1.createdAt }
    }

    var descendantCount: Int {
        (children ?? []).reduce(0) { $0 + 1 + $1.descendantCount }
    }

    var snippet: String { Markdown.snippet(markdownBody) }

    func touch() { updatedAt = .now }
}

enum NoteTemplate: String, CaseIterable, Identifiable {
    case blank, lecture, cheatSheet, reading

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .blank: "Blank page"
        case .lecture: "Lecture notes"
        case .cheatSheet: "Exam cheat-sheet"
        case .reading: "Reading summary"
        }
    }

    var systemImage: String {
        switch self {
        case .blank: "doc"
        case .lecture: "person.fill.viewfinder"
        case .cheatSheet: "list.bullet.rectangle"
        case .reading: "book"
        }
    }

    func make(course: Course?, parent: Note?, now: Date = .now) -> Note {
        let day = now.formatted(date: .abbreviated, time: .omitted)
        switch self {
        case .blank:
            return Note(title: "", markdownBody: "", course: course, parent: parent)
        case .lecture:
            return Note(title: "Lecture · \(day)", markdownBody: """
            ## Topic


            ## Key points
            - 

            ## Examples


            ## Questions to ask
            - [ ] 

            ## Next steps
            - [ ] 
            """, course: course, parent: parent)
        case .cheatSheet:
            return Note(title: "\(course?.name ?? "Exam") cheat-sheet", markdownBody: """
            ## Formulas & definitions
            | Term | Meaning |
            |---|---|
            |  |  |

            ## Things I always forget
            - 

            ## Worked example


            ## Last-minute checklist
            - [ ] Re-do past problems
            - [ ] Sleep
            """, course: course, parent: parent)
        case .reading:
            return Note(title: "Reading · \(day)", markdownBody: """
            ## Source


            ## Main idea


            ## Quotes
            > 

            ## My take


            ## To look up
            - [ ] 
            """, course: course, parent: parent)
        }
    }
}
