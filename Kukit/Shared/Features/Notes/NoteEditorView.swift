import SwiftUI
import SwiftData
import KukitCore

/// Edit a page: title, course, a Markdown editor with a formatting bar, and a live preview.
struct NoteEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var note: Note
    /// Opens another page (used for `[[links]]`).
    var onOpen: (Note) -> Void

    @Query(sort: \Note.title) private var allNotes: [Note]
    @Query(sort: \Course.name) private var allCourses: [Course]

    enum Mode: String, CaseIterable, Identifiable {
        case write = "Write", split = "Split", preview = "Preview"
        var id: String { rawValue }
    }

    #if os(macOS)
    @State private var mode: Mode = .split
    #else
    @State private var mode: Mode = .write
    #endif
    @State private var selection: TextSelection?
    @State private var applyingEdit = false
    @State private var showTaskPicker = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    private var availableModes: [Mode] {
        #if os(macOS)
        Mode.allCases
        #else
        [.write, .preview]
        #endif
    }

    var body: some View {
        // The page sits on the cream "desk" like a sheet of paper.
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            if mode != .preview { formattingBar; Divider().opacity(0.6) }
            content
        }
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border) }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        .padding(12)
        .kukitScreen()
        .navigationTitle(note.displayTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $mode) {
                    ForEach(availableModes) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            ToolbarItem(placement: .primaryAction) { menu }
        }
        .sheet(isPresented: $showTaskPicker) { LinkedTasksPicker(note: note) }
        .confirmationDialog(
            "Delete “\(note.displayTitle)”?", isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("Delete page\(note.descendantCount > 0 ? " and \(note.descendantCount) subpages" : "")", role: .destructive) {
                context.delete(note)
                try? context.save()
                dismiss()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $note.title)
                .font(.system(.title2, design: .serif, weight: .bold))
                .textFieldStyle(.plain)
                .onChange(of: note.title) { note.touch() }
            HStack(spacing: 10) {
                Menu {
                    Button("No course") { note.course = nil }
                    ForEach(allCourses.filter { !$0.isArchived }) { course in
                        Button(course.name) { note.course = course }
                    }
                } label: {
                    Label(note.course?.name ?? "No course", systemImage: "books.vertical")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button { note.isPinned.toggle() } label: {
                    Label(note.isPinned ? "Pinned" : "Pin", systemImage: note.isPinned ? "pin.fill" : "pin")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if !(note.assignments ?? []).isEmpty {
                    Label("\((note.assignments ?? []).count) linked", systemImage: "link")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Text(note.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 10)
    }

    private var menu: some View {
        Menu {
            Button("New subpage", systemImage: "doc.badge.plus") {
                let child = Note(title: "", course: note.course, parent: note)
                context.insert(child)
                try? context.save()
                onOpen(child)
            }
            Button("Link tasks…", systemImage: "link") { showTaskPicker = true }
            ShareLink(item: exportText, subject: Text(note.displayTitle)) {
                Label("Share as Markdown", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button("Delete page…", systemImage: "trash", role: .destructive) { confirmDelete = true }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    private var exportText: String {
        "# \(note.displayTitle)\n\n\(note.markdownBody)"
    }

    // MARK: Formatting bar

    private var formattingBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                formatButton("Heading", "textformat.size") { MarkdownEditing.setHeading($0, selection: $1, level: 2) }
                formatButton("Bold", "bold") { MarkdownEditing.toggleWrap($0, selection: $1, prefix: "**", placeholder: "bold") }
                    .keyboardShortcut("b", modifiers: .command)
                formatButton("Italic", "italic") { MarkdownEditing.toggleWrap($0, selection: $1, prefix: "*", placeholder: "italic") }
                    .keyboardShortcut("i", modifiers: .command)
                formatButton("Code", "chevron.left.forwardslash.chevron.right") {
                    MarkdownEditing.toggleWrap($0, selection: $1, prefix: "`", placeholder: "code")
                }
                Divider().frame(height: 18).padding(.horizontal, 4)
                formatButton("Bullet list", "list.bullet") { MarkdownEditing.toggleLinePrefix($0, selection: $1, prefix: "- ") }
                formatButton("Checklist", "checklist") { MarkdownEditing.toggleLinePrefix($0, selection: $1, prefix: "- [ ] ") }
                formatButton("Quote", "text.quote") { MarkdownEditing.toggleLinePrefix($0, selection: $1, prefix: "> ") }
                formatButton("Link", "link") {
                    MarkdownEditing.toggleWrap($0, selection: $1, prefix: "[", suffix: "](https://)", placeholder: "link text")
                }
                formatButton("Page link", "doc.text") {
                    MarkdownEditing.toggleWrap($0, selection: $1, prefix: "[[", suffix: "]]", placeholder: "Page title")
                }
                Divider().frame(height: 18).padding(.horizontal, 4)
                formatButton("Indent", "increase.indent") { MarkdownEditing.shiftIndent($0, selection: $1, outdent: false) }
                formatButton("Outdent", "decrease.indent") { MarkdownEditing.shiftIndent($0, selection: $1, outdent: true) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func formatButton(
        _ title: String, _ systemImage: String,
        _ edit: @escaping (String, Range<Int>) -> MarkdownEditing.Result
    ) -> some View {
        Button { apply(edit) } label: {
            Image(systemName: systemImage).frame(width: 30, height: 28)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .write:
            editor
        case .preview:
            preview
        case .split:
            #if os(macOS)
            HSplitView {
                editor.frame(minWidth: 260)
                preview.frame(minWidth: 260)
            }
            #else
            editor
            #endif
        }
    }

    private var editor: some View {
        TextEditor(text: $note.markdownBody, selection: $selection)
            .font(.system(.body, design: .serif))
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onChange(of: note.markdownBody) { old, new in
                note.touch()
                continueListIfNeeded(old: old, new: new)
            }
    }

    private var preview: some View {
        ScrollView {
            MarkdownPreview(
                source: note.markdownBody,
                onToggleLine: { line in
                    note.markdownBody = Markdown.toggleChecklist(in: note.markdownBody, line: line)
                },
                onOpenNote: openNote(titled:)
            )
            .fontDesign(.serif)
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Editing

    private func apply(_ edit: (String, Range<Int>) -> MarkdownEditing.Result) {
        let text = note.markdownBody
        let result = edit(text, currentRange(in: text))
        applyingEdit = true
        note.markdownBody = result.text
        selection = TextSelection(range: stringRange(result.selection, in: result.text))
        DispatchQueue.main.async { applyingEdit = false }
    }

    /// The selection as Character offsets (end of text when there is none).
    private func currentRange(in text: String) -> Range<Int> {
        if let indices = selection?.indices, case .selection(let range) = indices {
            let lower = text.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.distance(from: text.startIndex, to: range.upperBound)
            return lower..<upper
        }
        return text.count..<text.count
    }

    private func stringRange(_ range: Range<Int>, in text: String) -> Range<String.Index> {
        let lower = text.index(text.startIndex, offsetBy: min(range.lowerBound, text.count))
        let upper = text.index(text.startIndex, offsetBy: min(range.upperBound, text.count))
        return lower..<upper
    }

    /// Return at the end of a list item starts the next item (or ends the list on an empty one).
    private func continueListIfNeeded(old: String, new: String) {
        guard !applyingEdit, let position = MarkdownEditing.insertedNewline(old: old, new: new),
              let result = MarkdownEditing.continueList(old, cursor: position) else { return }
        applyingEdit = true
        note.markdownBody = result.text
        selection = TextSelection(range: stringRange(result.selection, in: result.text))
        DispatchQueue.main.async { applyingEdit = false }
    }

    // MARK: Links

    private func openNote(titled title: String) {
        let wanted = title.lowercased()
        if let existing = allNotes.first(where: { $0.title.trimmingCharacters(in: .whitespaces).lowercased() == wanted }) {
            onOpen(existing)
            return
        }
        let created = Note(title: title, course: note.course, parent: nil)
        context.insert(created)
        try? context.save()
        onOpen(created)
    }
}

/// Choose which tasks a page relates to.
struct LinkedTasksPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var note: Note
    @Query(sort: \Assignment.createdAt, order: .reverse) private var all: [Assignment]

    private var candidates: [Assignment] {
        let linked = Set((note.assignments ?? []).map(\.id))
        return all.filter { item in
            linked.contains(item.id) || !item.isDone && (note.course == nil || item.course?.id == note.course?.id)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    Text("No open tasks\(note.course.map { " for \($0.name)" } ?? "").")
                        .foregroundStyle(.secondary)
                }
                ForEach(candidates) { item in
                    Button { toggle(item) } label: {
                        HStack {
                            Image(systemName: isLinked(item) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isLinked(item) ? Theme.accent : Color.secondary)
                            VStack(alignment: .leading) {
                                Text(item.title).foregroundStyle(.primary)
                                Text([item.course?.name, item.dueDescription].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .kukitList()
        .navigationTitle("Link tasks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 420)
        #endif
    }

    private func isLinked(_ item: Assignment) -> Bool {
        (note.assignments ?? []).contains { $0.id == item.id }
    }

    private func toggle(_ item: Assignment) {
        var current = note.assignments ?? []
        if let index = current.firstIndex(where: { $0.id == item.id }) {
            current.remove(at: index)
        } else {
            current.append(item)
        }
        note.assignments = current
        try? context.save()
    }
}
