import SwiftUI
import SwiftData
import KukitCore

/// Every assignment, quiz, project, lab and exam: today, upcoming, a week calendar, by course.
struct AssignmentsView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @Query(sort: \Assignment.createdAt, order: .reverse) private var all: [Assignment]
    @Query(sort: \Course.name) private var allCourses: [Course]

    enum Mode: String, CaseIterable, Identifiable {
        case today = "Today"
        case upcoming = "Upcoming"
        case week = "Week"
        case courses = "Courses"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .today
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

    private var overdueCount: Int { open.filter { $0.dueBucket == .overdue }.count }

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
            case .today: todayList
            case .upcoming: upcomingList
            case .week:
                WeekCalendarView(assignments: open + completed) { editorTarget = .edit($0) }
            case .courses: byCourseList
            }
        }
        .kukitScreen()
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

    /// Today's ingredients: what's overdue or due today, plus what you've already prepared today.
    private var todayList: some View {
        let todays = open.filter { $0.dueBucket == .overdue || $0.dueBucket == .today }
        let doneToday = completed.filter { $0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false }
        return List {
            if courses.isEmpty {
                noCoursesState
            } else {
                KSection { QuickAddRow(courses: courses, defaultCourseID: courseFilter) }
            }

            if !courses.isEmpty && todays.isEmpty {
                KSection {
                    EmptyStateView(
                        mood: doneToday.isEmpty ? .noTasks : .celebrate,
                        title: doneToday.isEmpty ? "Nothing on the menu today" : "Today's ingredients are prepared",
                        message: doneToday.isEmpty ? Chef.line(.emptyTasks, seed: Chef.daySeed()) : Chef.line(.taskComplete, seed: Chef.daySeed())
                    )
                    .listRowInsets(EdgeInsets())
                }
            }

            if !todays.isEmpty {
                KSection {
                    ForEach(todays) { item in row(item) }
                } header: {
                    Label(overdueCount > 0 ? "To prepare · \(overdueCount) overdue" : "To prepare", systemImage: "fork.knife")
                        .foregroundStyle(overdueCount > 0 ? Theme.accentText : Color.secondary)
                }
            }

            if !doneToday.isEmpty {
                KSection {
                    ForEach(doneToday) { item in row(item) }
                } header: {
                    Label("Prepared today", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.basilText)
                }
            }
        }
        .kukitList()
    }

    private var upcomingList: some View {
        List {
            if courses.isEmpty {
                noCoursesState
            } else {
                KSection { QuickAddRow(courses: courses, defaultCourseID: courseFilter) }
            }

            ForEach(DueBucket.allCases, id: \.self) { bucket in
                let items = open.filter { $0.dueBucket == bucket }
                if !items.isEmpty {
                    KSection {
                        ForEach(items) { item in row(item) }
                    } header: {
                        Label(bucket.title, systemImage: icon(for: bucket))
                            .foregroundStyle(bucket == .overdue ? Theme.accentText : Color.secondary)
                    }
                }
            }

            if !courses.isEmpty && open.isEmpty {
                KSection {
                    EmptyStateView(
                        mood: .noTasks, title: "No open tasks",
                        message: Chef.line(.emptyTasks, seed: Chef.daySeed())
                    )
                }
            }

            if !completed.isEmpty {
                KSection {
                    DisclosureGroup("Completed (\(completed.count))", isExpanded: $showCompleted) {
                        ForEach(completed.prefix(50)) { item in row(item) }
                    }
                    .font(.kukit(.subheadline, weight: .bold))
                }
            }
        }
        .kukitList()
    }

    private var byCourseList: some View {
        List {
            ForEach(courses) { course in
                let items = open.filter { $0.course?.id == course.id }
                if !items.isEmpty {
                    KSection {
                        ForEach(items) { item in row(item, showsCourse: false) }
                    } header: {
                        HStack(spacing: 8) {
                            CourseBadge(color: course.color, symbol: course.symbolName, size: 22)
                            Text(course.name)
                        }
                    }
                }
            }
            if open.isEmpty {
                KSection {
                    EmptyStateView(mood: .noTasks, title: "No open tasks", message: Chef.line(.emptyTasks, seed: Chef.daySeed()))
                }
            }
        }
        .kukitList()
    }

    private var noCoursesState: some View {
        KSection {
            EmptyStateView(
                mood: .idle, title: "Add a course first",
                message: "Tasks belong to a course. Add one in Courses, then come back to prepare your ingredients."
            )
        }
    }

    private func icon(for bucket: DueBucket) -> String {
        switch bucket {
        case .overdue: "exclamationmark.circle.fill"
        case .today: "clock.fill"
        case .nextSevenDays: "calendar"
        case .later: "calendar.badge.clock"
        case .noDate: "tray"
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
                .tint(Theme.basil)
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
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                TextField("Add an ingredient…", text: $title)
                    .onSubmit(add)
                    .submitLabel(.done)
                    .font(.kukit(.body, weight: .semibold))
                if !title.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add", action: add).buttonStyle(.kukit(.ghost))
                }
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(courses) { course in
                        Button(course.name) { courseID = course.id }
                    }
                } label: {
                    Label(effectiveCourse?.name ?? "Course", systemImage: "books.vertical.fill")
                }
                Menu {
                    ForEach(QuickDue.allCases) { option in
                        Button(option.rawValue) { due = option }
                    }
                } label: {
                    Label(due.rawValue, systemImage: "calendar")
                }
            }
            .font(.kukit(.footnote, weight: .semibold))
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
        Haptics.play(.tap)
        title = ""
    }
}
