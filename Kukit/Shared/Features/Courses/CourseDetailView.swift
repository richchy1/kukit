import SwiftUI
import SwiftData
import KukitCore

/// A course workspace: study time, tasks, grade, notes and sessions in the course's color.
struct CourseDetailView: View {
    @Environment(TimerController.self) private var timer
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var course: Course
    @Query(sort: \GradingScale.createdAt) private var scales: [GradingScale]
    @Query(sort: [SortDescriptor(\TimerPreset.sortOrder), SortDescriptor(\TimerPreset.createdAt)])
    private var presets: [TimerPreset]
    @State private var showingEdit = false
    @State private var taskEditor: TaskEditor?

    private enum TaskEditor: Identifiable {
        case new
        case edit(Assignment)
        var id: String {
            switch self {
            case .new: "new"
            case .edit(let a): a.id.uuidString
            }
        }
    }

    private var openTasks: [Assignment] {
        Assignment.sortedByUrgency((course.assignments ?? []).filter { !$0.isDone })
    }

    private var doneCount: Int { (course.assignments ?? []).filter(\.isDone).count }
    private var totalTasks: Int { (course.assignments ?? []).count }

    private var sessions: [StudySession] {
        (course.sessions ?? []).sorted { $0.startedAt > $1.startedAt }
    }

    private var notes: [Note] {
        (course.notes ?? []).sorted { $0.updatedAt > $1.updatedAt }
    }

    private var weekSeconds: TimeInterval {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return sessions.filter { $0.startedAt >= start }.reduce(0) { $0 + $1.focusSeconds }
    }

    private var totalSeconds: TimeInterval { sessions.reduce(0) { $0 + $1.focusSeconds } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero

                Button {
                    Haptics.play(.heavy)
                    timer.selectCourse(course.id)
                    timer.start(config: PresetCatalog.resolve(id: timer.selectedPresetID, custom: presets))
                    router.section = .focus
                } label: {
                    Label("Start Cooking", systemImage: "flame.fill")
                        .font(.kukit(.headline, weight: .heavy))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.kukit(.primary, tint: course.color))
                .disabled(course.isArchived || timer.state.isActive)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                    StatTile(title: "This week", value: DurationFormat.short(weekSeconds), systemImage: "clock.fill", tint: course.color)
                    StatTile(title: "All time", value: DurationFormat.short(totalSeconds), systemImage: "flame.fill")
                    StatTile(title: "Sessions", value: "\(sessions.count)", systemImage: "checkmark.circle.fill")
                }

                gradeCard
                tasksCard
                notesCard
                sessionsCard
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            ZStack(alignment: .top) {
                KukitBackground()
                LinearGradient(colors: [course.color.opacity(0.20), .clear], startPoint: .top, endPoint: .center)
                    .frame(height: 360)
            }
            .ignoresSafeArea()
        )
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
        .sheet(item: $taskEditor) { target in
            switch target {
            case .new: AssignmentEditorView(assignment: nil, defaultCourseID: course.id)
            case .edit(let assignment): AssignmentEditorView(assignment: assignment)
            }
        }
    }

    // MARK: Sections

    private var hero: some View {
        HStack(spacing: 16) {
            CourseBadge(color: course.color, symbol: course.symbolName, size: 68)
            VStack(alignment: .leading, spacing: 5) {
                Text(course.name).font(.kukit(.title, weight: .heavy)).fixedSize(horizontal: false, vertical: true)
                Text([course.code, course.instructor].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.kukit(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Chip(text: "\(course.credits.formatted(.number.precision(.fractionLength(0...1)))) credits", systemImage: "number", tint: course.color)
                    if let semester = course.semester { Chip(text: semester.name, systemImage: "calendar", tint: Theme.ink.opacity(0.7)) }
                    if course.isArchived { Chip(text: "Archived", systemImage: "archivebox.fill", tint: Theme.ink.opacity(0.7)) }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var gradeCard: some View {
        let summary = course.gradeSummary
        let scale = GradingScales.resolve(for: course, in: scales)
        let band = summary.currentPercent.flatMap { scale.band(for: $0) }
        return NavigationLink {
            CourseGradesView(course: course)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(course.color.opacity(0.15)).frame(width: 52, height: 52)
                    if let band {
                        Text(band.label).font(.kukit(.title3, weight: .heavy)).foregroundStyle(course.color)
                    } else {
                        Image(systemName: "graduationcap.fill").foregroundStyle(course.color)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grade").font(.kukit(.headline, weight: .heavy)).foregroundStyle(Theme.ink)
                    if course.hasGrades {
                        Text(summary.currentPercent == nil
                             ? "No scores yet"
                             : "\(GradeFormat.percent(summary.currentPercent)) now → \(GradeFormat.percent(summary.projectedPercent)) projected")
                            .font(.kukit(.subheadline, weight: .medium)).foregroundStyle(.secondary)
                    } else {
                        Text("Set up weights and see what you need on the final")
                            .font(.kukit(.subheadline, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .card()
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: Theme.cardRadius)
    }

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Ingredients", systemImage: "fork.knife")
                Button("Add task", systemImage: "plus") { taskEditor = .new }
                    .buttonStyle(.kukit(.ghost))
                    .disabled(course.isArchived)
            }
            if totalTasks > 0 {
                HStack(spacing: 10) {
                    RecipeBar(progress: Double(doneCount) / Double(totalTasks), tint: Theme.basil, height: 8)
                    Text("\(doneCount) of \(totalTasks) prepared")
                        .font(.kukit(.caption, weight: .bold)).foregroundStyle(.secondary).fixedSize()
                }
            }
            if openTasks.isEmpty {
                Text(totalTasks == 0 ? "No tasks yet for this course." : "Everything is prepared. Suspiciously productive.")
                    .font(.kukit(.subheadline, weight: .medium)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(openTasks.prefix(6)) { item in
                        AssignmentRow(assignment: item, showsCourse: false) { taskEditor = .edit(item) }
                            .padding(.vertical, 8)
                        if item.id != openTasks.prefix(6).last?.id { Divider().opacity(0.6) }
                    }
                }
            }
        }
        .card(padding: 18)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Recipe cards", systemImage: "note.text")
            if notes.isEmpty {
                Text("No notes for this course yet. Add one from the Notes tab.")
                    .font(.kukit(.subheadline, weight: .medium)).foregroundStyle(.secondary)
            } else {
                ForEach(notes.prefix(4)) { note in
                    Button {
                        router.pendingNoteID = note.id
                        router.section = .notes
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text").foregroundStyle(course.color)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(note.displayTitle).font(.system(.subheadline, design: .serif, weight: .semibold)).foregroundStyle(Theme.ink)
                                if !note.snippet.isEmpty {
                                    Text(note.snippet).font(.kukit(.caption, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                }
            }
        }
        .card(padding: 18)
    }

    private var sessionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle("Cookbook", systemImage: "book.closed.fill")
                if sessions.count > 5 {
                    NavigationLink("See all") { HistoryView(course: course) }
                        .font(.kukit(.subheadline, weight: .bold))
                }
            }
            if sessions.isEmpty {
                Text(Chef.line(.emptyHistory, seed: Chef.daySeed()))
                    .font(.kukit(.subheadline, weight: .medium)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(sessions.prefix(5)) { session in
                        SessionRow(session: session, showsCourse: false)
                            .padding(.vertical, 8)
                        if session.id != sessions.prefix(5).last?.id { Divider().opacity(0.6) }
                    }
                }
            }
        }
        .card(padding: 18)
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
