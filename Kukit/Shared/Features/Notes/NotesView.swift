import SwiftUI
import SwiftData
import KukitCore

/// Pages for your courses: pinned, recent and nested, with search across notes, tasks and courses.
/// iPhone pushes the editor; Mac shows the list and the editor side by side.
struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(TimerController.self) private var timer
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \Course.name) private var allCourses: [Course]
    @Query(sort: \Assignment.createdAt, order: .reverse) private var allTasks: [Assignment]

    @State private var search = ""
    @State private var courseFilter: UUID?
    @State private var selection: Note?
    @State private var editingTask: Assignment?
    @State private var pendingDelete: Note?
    #if os(iOS)
    @State private var path: [Note] = []
    #endif

    private var courses: [Course] { allCourses.filter { !$0.isArchived } }
    private var trimmedSearch: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !trimmedSearch.isEmpty }

    private func inScope(_ note: Note) -> Bool {
        courseFilter == nil || note.course?.id == courseFilter
    }

    private var pinned: [Note] { allNotes.filter { $0.isPinned && inScope($0) } }
    private var recent: [Note] { Array(allNotes.filter { !$0.isPinned && inScope($0) }.prefix(4)) }
    private var roots: [Note] {
        allNotes.filter { $0.parent == nil && inScope($0) }
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    private var noteResults: [Note] {
        allNotes.filter { inScope($0) && (
            $0.title.localizedCaseInsensitiveContains(trimmedSearch)
            || $0.markdownBody.localizedCaseInsensitiveContains(trimmedSearch)) }
    }
    private var taskResults: [Assignment] {
        allTasks.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedSearch)
            || $0.details.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }
    private var courseResults: [Course] {
        courses.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedSearch)
            || $0.code.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    var body: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            listPane.frame(width: 300)
            Divider()
            detailPane
        }
        .navigationTitle("Notes")
        .toolbar { toolbarItems }
        .modifier(sharedModifiers)
        #else
        NavigationStack(path: $path) {
            listPane
                .navigationTitle("Notes")
                .toolbar { toolbarItems }
                .navigationDestination(for: Note.self) { note in
                    NoteEditorView(note: note) { open($0) }
                }
        }
        .modifier(sharedModifiers)
        #endif
    }

    // MARK: Shared pieces

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(NoteTemplate.allCases) { template in
                    Button { create(template) } label: { Label(template.menuTitle, systemImage: template.systemImage) }
                }
            } label: {
                Label("New page", systemImage: "square.and.pencil")
            }
        }
        ToolbarItem(placement: .automatic) {
            Menu {
                Picker("Course", selection: $courseFilter) {
                    Text("All courses").tag(UUID?.none)
                    ForEach(courses) { Text($0.name).tag(Optional($0.id)) }
                }
            } label: {
                Label("Filter", systemImage: courseFilter == nil
                      ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
        }
    }

    private var sharedModifiers: some ViewModifier {
        NotesModifiers(
            search: $search, editingTask: $editingTask, pendingDelete: $pendingDelete,
            delete: delete(_:)
        )
    }

    private var listPane: some View {
        #if os(macOS)
        List(selection: $selection) { listContent }
            .listStyle(.sidebar)
        #else
        List { listContent }
        #endif
    }

    @ViewBuilder
    private var listContent: some View {
        if isSearching {
            searchResults
        } else if allNotes.isEmpty {
            EmptyStateView(
                systemImage: "note.text",
                title: "No notes yet",
                message: "Write lecture notes, exam cheat-sheets and reading summaries in Markdown.",
                actionTitle: "New page"
            ) { create(.blank) }
            .listRowBackground(Color.clear)
        } else {
            if !pinned.isEmpty {
                Section("Pinned") { ForEach(pinned) { row($0) } }
            }
            if !recent.isEmpty {
                Section("Recent") { ForEach(recent) { row($0) } }
            }
            Section("All pages") {
                OutlineGroup(roots, children: \.childNotes) { row($0) }
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let notes = noteResults, tasks = taskResults, found = courseResults
        if notes.isEmpty && tasks.isEmpty && found.isEmpty {
            Text("No matches for “\(trimmedSearch)”.").foregroundStyle(.secondary)
        }
        if !notes.isEmpty {
            Section("Notes") { ForEach(notes) { row($0, showsSnippetMatch: true) } }
        }
        if !tasks.isEmpty {
            Section("Tasks") {
                ForEach(tasks.prefix(15)) { task in
                    Button { editingTask = task } label: {
                        HStack {
                            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.course?.color ?? Color.secondary)
                            VStack(alignment: .leading) {
                                Text(task.title)
                                Text([task.course?.name, task.dueDescription].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !found.isEmpty {
            Section("Courses") {
                ForEach(found) { course in
                    Button {
                        timer.selectCourse(course.id)
                        router.section = .courses
                    } label: {
                        HStack {
                            CourseBadge(color: course.color, symbol: course.symbolName, size: 26)
                            Text(course.name)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ note: Note, showsSnippetMatch: Bool = false) -> some View {
        let label = NoteRow(note: note)
        Group {
            #if os(macOS)
            label.tag(note)
            #else
            NavigationLink(value: note) { label }
            #endif
        }
        .contextMenu {
            Button(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin") {
                note.isPinned.toggle()
            }
            Button("New subpage", systemImage: "doc.badge.plus") { create(.blank, parent: note) }
            Button("Delete…", systemImage: "trash", role: .destructive) { pendingDelete = note }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = note }
        }
        .swipeActions(edge: .leading) {
            Button(note.isPinned ? "Unpin" : "Pin", systemImage: "pin") { note.isPinned.toggle() }
                .tint(Theme.accent)
        }
    }

    // MARK: Detail (Mac)

    #if os(macOS)
    @ViewBuilder
    private var detailPane: some View {
        if let note = selection {
            NoteEditorView(note: note) { open($0) }
                .id(note.id)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "note.text").font(.system(size: 40)).foregroundStyle(.tertiary)
                Text("Select a page, or create one").foregroundStyle(.secondary)
                Button("New page") { create(.blank) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    #endif

    // MARK: Actions

    private func open(_ note: Note) {
        #if os(macOS)
        selection = note
        #else
        path.append(note)
        #endif
    }

    private func create(_ template: NoteTemplate, parent: Note? = nil) {
        let course = allCourses.first { $0.id == (courseFilter ?? parent?.course?.id) }
        let note = template.make(course: course, parent: parent)
        context.insert(note)
        try? context.save()
        search = ""
        open(note)
    }

    private func delete(_ note: Note) {
        #if os(macOS)
        if selection == note { selection = nil }
        #else
        path.removeAll { $0 == note }
        #endif
        context.delete(note)
        try? context.save()
    }
}

private struct NotesModifiers: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var search: String
    @Binding var editingTask: Assignment?
    @Binding var pendingDelete: Note?
    var delete: (Note) -> Void

    func body(content: Content) -> some View {
        content
            .searchable(text: $search, prompt: "Search notes, tasks, courses")
            .sheet(item: $editingTask) { AssignmentEditorView(assignment: $0) }
            .confirmationDialog(
                "Delete “\(pendingDelete?.displayTitle ?? "page")”?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete page\((pendingDelete?.descendantCount ?? 0) > 0 ? " and subpages" : "")", role: .destructive) {
                    if let note = pendingDelete { delete(note) }
                    pendingDelete = nil
                }
            }
    }
}

struct NoteRow: View {
    var note: Note

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: (note.children ?? []).isEmpty ? "doc.text" : "doc.on.doc")
                .foregroundStyle(note.course?.color ?? Color.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(note.displayTitle).font(.body.weight(.medium)).lineLimit(1)
                    if note.isPinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Theme.accent) }
                }
                let snippet = note.snippet
                if !snippet.isEmpty {
                    Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
