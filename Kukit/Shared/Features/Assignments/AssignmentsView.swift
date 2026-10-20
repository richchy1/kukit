import SwiftUI
import SwiftData
import KukitCore

struct AssignmentsView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @Query(sort: \Assignment.createdAt, order: .reverse) private var all: [Assignment]
    @Query(sort: \Course.name) private var allCourses: [Course]

    enum Mode: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming"
        case week = "Week"
        case courses = "By course"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .upcoming
    @State private var search = ""
    @State private var courseFilter: UUID?
    @State private var typeFilter: AssignmentType?
    @State private var editorTarget: EditorTarget?
    @State private var showCompleted = false

    private enum EditorTarget: Identifiable {
        case new
        case edit(Assignment)
        var id: String {
            switch self {
            case .new: "new"
            case .edit(let a): a.id.uuidString
            }
        }
    }

    private var courses: [Course] { allCourses.filter { !$0.isArchived } }

    private var filtered: [Assignment] {
        all.filter { item in
            if let courseFilter, item.course?.id != courseFilter { return false }
            if let typeFilter, item.type != typeFilter { return false }
            if !search.isEmpty, !item.title.localizedCaseInsensitiveContains(search),
               !(item.course?.name.localizedCaseInsensitiveContains(search) ?? false) { return false }
            return true
        }
    }

    private var open: [Assignment] { Assignment.sortedByUrgency(filtered.filter { !$0.isDone }) }
    private var completed: [Assignment] {
        filtered.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            switch mode {
            case .upcoming: upcomingList
            case .week:
                WeekCalendarView(assignments: open + completed) { editorTarget = .edit($0) }
            case .courses: byCourseList
            }
        }
        .background(Theme.screenBackground)
        .navigationTitle("Tasks")
        .searchable(text: $search, prompt: "Search tasks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New task", systemImage: "plus") { editorTarget = .new }
                    .disabled(courses.isEmpty)
            }
            ToolbarItem(placement: .automatic) { filterMenu }
        }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new: AssignmentEditorView(assignment: nil, defaultCourseID: timer.selectedCourseID ?? courseFilter)
            case .edit(let assignment): AssignmentEditorView(assignment: assignment)
            }
        }
    }

    // MARK: Lists

    private var upcomingList: some View {
        List {
            if courses.isEmpty {
                EmptyStateView(
                    systemImage: "checklist",
                    title: "Add a course first",
                    message: "Tasks belong to a course. Add one in the Courses tab, then come back."
                )
                .listRowBackground(Color.clear)
            } else {
                Section { QuickAddRow(courses: courses, defaultCourseID: courseFilter) }
            }

            if !courses.isEmpty && all.isEmpty {
                Text("Nothing to do yet. Type a task above, or tap + for more options.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(DueBucket.allCases, id: \.self) { bucket in
                let items = open.filter { $0.dueBucket == bucket }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in row(item) }
                    } header: {
                        Text(bucket.title)
                            .foregroundStyle(bucket == .overdue ? Color.red : Color.secondary)
                    }
                }
            }

            if !completed.isEmpty {
                Section {
                    DisclosureGroup("Completed (\(completed.count))", isExpanded: $showCompleted) {
                        ForEach(completed.prefix(50)) { item in row(item) }
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private var byCourseList: some View {
        List {
            ForEach(courses) { course in
                let items = open.filter { $0.course?.id == course.id }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in row(item, showsCourse: false) }
                    } header: {
                        HStack(spacing: 8) {
                            CourseBadge(color: course.color, symbol: course.symbolName, size: 20)
                            Text(course.name)
                        }
                    }
                }
            }
            if open.isEmpty {
                Text("No open tasks.").foregroundStyle(.secondary).listRowBackground(Color.clear)
            }
        }
    }

    private func row(_ item: Assignment, showsCourse: Bool = true) -> some View {
        AssignmentRow(assignment: item, showsCourse: showsCourse) { editorTarget = .edit(item) }
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    AssignmentActions.delete(item, context: context)
                }
            }
            .swipeActions(edge: .leading) {
                Button(item.isDone ? "Reopen" : "Done", systemImage: "checkmark") {
                    AssignmentActions.setDone(item, !item.isDone, context: context)
                }
                .tint(.green)
            }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Course", selection: $courseFilter) {
                Text("All courses").tag(UUID?.none)
                ForEach(courses) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Type", selection: $typeFilter) {
                Text("All types").tag(AssignmentType?.none)
                ForEach(AssignmentType.allCases) { Text($0.title).tag(Optional($0)) }
            }
        } label: {
            Label("Filter", systemImage: courseFilter == nil && typeFilter == nil
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }
}

/// Type a task, pick a course and (optionally) a day, press return.
struct QuickAddRow: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    var courses: [Course]
    var defaultCourseID: UUID?

    @State private var title = ""
    @State private var courseID: UUID?
    @State private var due: QuickDue = .none

    enum QuickDue: String, CaseIterable, Identifiable {
        case none = "No date", today = "Today", tomorrow = "Tomorrow", nextWeek = "In a week"
        var id: String { rawValue }

        var date: Date? {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            switch self {
            case .none: return nil
            case .today: return today
            case .tomorrow: return calendar.date(byAdding: .day, value: 1, to: today)
            case .nextWeek: return calendar.date(byAdding: .day, value: 7, to: today)
            }
        }
    }

    private var effectiveCourse: Course? {
        courses.first { $0.id == (courseID ?? defaultCourseID ?? timer.selectedCourseID) } ?? courses.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                TextField("Add a task…", text: $title)
                    .onSubmit(add)
                    .submitLabel(.done)
                if !title.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add", action: add).buttonStyle(.borderless)
                }
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(courses) { course in
                        Button(course.name) { courseID = course.id }
                    }
                } label: {
                    Label(effectiveCourse?.name ?? "Course", systemImage: "books.vertical")
                }
                Menu {
                    ForEach(QuickDue.allCases) { option in
                        Button(option.rawValue) { due = option }
                    }
                } label: {
                    Label(due.rawValue, systemImage: "calendar")
                }
            }
            .font(.footnote)
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func add() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let course = effectiveCourse else { return }
        let item = Assignment(title: trimmed, course: course, dueDate: due.date, hasDueTime: false)
        context.insert(item)
        AssignmentActions.persist(item, context: context)
        title = ""
    }
}
