import SwiftUI
import SwiftData
import KukitCore

struct CourseDetailView: View {
    @Environment(TimerController.self) private var timer
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var course: Course
    @State private var showingEdit = false

    private var sessions: [StudySession] {
        (course.sessions ?? []).sorted { $0.startedAt > $1.startedAt }
    }

    private var weekSeconds: TimeInterval {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return sessions.filter { $0.startedAt >= start }.reduce(0) { $0 + $1.focusSeconds }
    }

    private var totalSeconds: TimeInterval { sessions.reduce(0) { $0 + $1.focusSeconds } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                    StatTile(title: "This week", value: DurationFormat.short(weekSeconds))
                    StatTile(title: "All time", value: DurationFormat.short(totalSeconds))
                    StatTile(title: "Sessions", value: "\(sessions.count)")
                }

                Button {
                    timer.selectCourse(course.id)
                    router.section = .focus
                } label: {
                    Label("Start focus", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(course.color)
                .disabled(course.isArchived || timer.state.isActive)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recent sessions").font(.headline)
                        Spacer()
                        if sessions.count > 5 {
                            NavigationLink("See all") { HistoryView(course: course) }
                                .font(.subheadline)
                        }
                    }
                    if sessions.isEmpty {
                        Text("No sessions yet. Start a focus session to log your first one.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .card()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(sessions.prefix(5)) { session in
                                SessionRow(session: session, showsCourse: false)
                                    .padding(.vertical, 10)
                                if session.id != sessions.prefix(5).last?.id { Divider() }
                            }
                        }
                        .card(padding: 14)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.screenBackground)
        .navigationTitle(course.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") { showingEdit = true }
            }
        }
                .sheet(isPresented: $showingEdit) {
            CourseEditorView(course: course, onDelete: deleteCourse)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            CourseBadge(color: course.color, symbol: course.symbolName, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(course.name).font(.title2.weight(.semibold))
                Text([course.code, course.instructor].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("\(course.credits.formatted(.number.precision(.fractionLength(0...1)))) credits")
                    if let semester = course.semester { Text("· \(semester.name)") }
                    if course.isArchived { Text("· Archived") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Step away from this screen first, then delete, so nothing reads a deleted course.
    private func deleteCourse() {
        let target = course
        if timer.selectedCourseID == target.id { timer.selectCourse(nil) }
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            context.delete(target)
            try? context.save()
        }
    }
}
