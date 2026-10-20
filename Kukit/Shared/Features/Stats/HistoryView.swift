import SwiftUI
import SwiftData
import KukitCore

struct SessionRow: View {
    var session: StudySession
    var showsCourse = true

    var body: some View {
        HStack(spacing: 12) {
            if showsCourse {
                CourseBadge(
                    color: session.course?.color ?? .secondary,
                    symbol: session.course?.symbolName ?? "questionmark",
                    size: 32
                )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.course?.name ?? "Deleted course")
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(DurationFormat.short(session.focusSeconds))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let when = session.startedAt.formatted(date: .abbreviated, time: .shortened)
        var parts = [when, session.presetName]
        if !session.comment.isEmpty { parts.append(session.comment) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Every saved session, newest first, grouped by day. Optionally limited to one course.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query private var sessions: [StudySession]
    @State private var editing: StudySession?
    private let course: Course?

    init(course: Course? = nil) {
        self.course = course
        if let id = course?.id {
            _sessions = Query(
                filter: #Predicate<StudySession> { $0.course?.id == id },
                sort: \.startedAt, order: .reverse
            )
        } else {
            _sessions = Query(sort: \.startedAt, order: .reverse)
        }
    }

    private struct DayGroup: Identifiable {
        var day: Date
        var sessions: [StudySession]
        var id: Date { day }
    }

    private var groups: [DayGroup] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
        return byDay.keys.sorted(by: >).map { DayGroup(day: $0, sessions: byDay[$0] ?? []) }
    }

    var body: some View {
        List {
            if sessions.isEmpty {
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: "No sessions yet",
                    message: "Finished focus sessions show up here."
                )
                .listRowBackground(Color.clear)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.sessions) { session in
                        Button { editing = session } label: {
                            SessionRow(session: session, showsCourse: course == nil)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(session) }
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editing = session }
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(session) }
                        }
                    }
                } header: {
                    HStack {
                        Text(group.day, format: .dateTime.weekday(.wide).month().day())
                        Spacer()
                        Text(DurationFormat.short(group.sessions.reduce(0) { $0 + $1.focusSeconds }))
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle(course.map { "\($0.name) sessions" } ?? "History")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editing) { SessionEditorView(session: $0) }
    }

    private func delete(_ session: StudySession) {
        context.delete(session)
        try? context.save()
    }
}

struct SessionEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.name) private var courses: [Course]

    let session: StudySession
    @State private var courseID: UUID?
    @State private var minutes: Int
    @State private var comment: String
    @State private var startedAt: Date

    init(session: StudySession) {
        self.session = session
        _courseID = State(initialValue: session.course?.id)
        _minutes = State(initialValue: max(1, Int((session.focusSeconds / 60).rounded())))
        _comment = State(initialValue: session.comment)
        _startedAt = State(initialValue: session.startedAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Course", selection: $courseID) {
                    ForEach(courses) { Text($0.name).tag(Optional($0.id)) }
                }
                DatePicker("Started", selection: $startedAt)
                NumberRow(title: "Focus time", unit: "min", value: $minutes, range: 1...600)
                Section("Note") {
                    TextField("What did you cover?", text: $comment, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit session")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    private func save() {
        session.course = courses.first { $0.id == courseID } ?? session.course
        session.startedAt = startedAt
        session.focusSeconds = Double(minutes) * 60
        session.endedAt = startedAt.addingTimeInterval(session.focusSeconds)
        session.comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
        dismiss()
    }
}
