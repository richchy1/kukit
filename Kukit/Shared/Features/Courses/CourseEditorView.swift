import SwiftUI
import SwiftData
import KukitCore

/// Create or edit a course. Pass `nil` to create.
struct CourseEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TimerController.self) private var timer
    @Query(sort: \Semester.startDate, order: .reverse) private var semesters: [Semester]

    var course: Course?
    /// Deleting is done by the caller after this sheet closes, so a screen showing the course can step away first.
    let onDelete: (() -> Void)?

    @State private var name: String
    @State private var code: String
    @State private var credits: Double
    @State private var colorHex: String
    @State private var symbol: String
    @State private var instructor: String
    @State private var countsTowardGPA: Bool
    @State private var isArchived: Bool
    @State private var semesterID: UUID?
    @State private var newSemesterName = ""
    @State private var confirmDelete = false

    init(course: Course?, onDelete: (() -> Void)? = nil) {
        self.course = course
        self.onDelete = onDelete
        _name = State(initialValue: course?.name ?? "")
        _code = State(initialValue: course?.code ?? "")
        _credits = State(initialValue: course?.credits ?? 3)
        _colorHex = State(initialValue: course?.colorHex ?? CoursePalette.colors[0].hex)
        _symbol = State(initialValue: course?.symbolName ?? "book.closed")
        _instructor = State(initialValue: course?.instructor ?? "")
        _countsTowardGPA = State(initialValue: course?.countsTowardGPA ?? true)
        _isArchived = State(initialValue: course?.isArchived ?? false)
        _semesterID = State(initialValue: course?.semester?.id)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Course name", text: $name)
                    TextField("Code (e.g. MATH201)", text: $code)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                    TextField("Instructor", text: $instructor)
                }

                Section("Credits") {
                    Stepper(value: $credits, in: 0...12, step: 0.5) {
                        Text("\(credits.formatted(.number.precision(.fractionLength(0...1)))) credits")
                    }
                    Toggle("Counts toward GPA", isOn: $countsTowardGPA)
                }

                Section("Semester") {
                    Picker("Semester", selection: $semesterID) {
                        Text("None").tag(UUID?.none)
                        ForEach(semesters) { semester in
                            Text(semester.name).tag(Optional(semester.id))
                        }
                    }
                    HStack {
                        TextField("New semester (e.g. Fall 2026)", text: $newSemesterName)
                            .onSubmit(addSemester)
                        Button("Add", action: addSemester)
                            .disabled(newSemesterName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Look") {
                    colorGrid
                    symbolGrid
                }

                if course != nil {
                    Section {
                        Toggle("Archived", isOn: $isArchived)
                        if onDelete != nil {
                            Button("Delete course…", role: .destructive) { confirmDelete = true }
                        }
                    } footer: {
                        Text("Archiving hides the course but keeps its sessions. Deleting removes everything linked to it.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(course == nil ? "New course" : "Edit course")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog(
                "Delete \(course?.name ?? "course")?", isPresented: $confirmDelete, titleVisibility: .visible
            ) {
                Button("Delete course and its sessions", role: .destructive, action: deleteCourse)
            } message: {
                Text("This also deletes \(course?.sessions?.count ?? 0) study sessions. Archive instead to keep them.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 620)
        #endif
    }

    // MARK: Pickers

    private var colorGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 10)], spacing: 10) {
            ForEach(CoursePalette.colors) { swatch in
                Button { colorHex = swatch.hex } label: {
                    Circle()
                        .fill(Color(hex: swatch.hex))
                        .frame(width: 32, height: 32)
                        .overlay {
                            if swatch.hex == colorHex {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(swatch.hex == colorHex ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 8)], spacing: 8) {
            ForEach(CoursePalette.symbols, id: \.self) { name in
                Button { symbol = name } label: {
                    Image(systemName: name)
                        .font(.body)
                        .frame(width: 36, height: 36)
                        .foregroundStyle(name == symbol ? Color.white : Color.primary)
                        .background(
                            name == symbol ? Color(hex: colorHex) : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(name == symbol ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Actions

    private func addSemester() {
        let trimmed = newSemesterName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let semester = Semester(name: trimmed)
        context.insert(semester)
        semesterID = semester.id
        newSemesterName = ""
    }

    private func save() {
        let target: Course
        if let course {
            target = course
        } else {
            target = Course(name: trimmedName)
            context.insert(target)
        }
        target.name = trimmedName
        target.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        target.instructor = instructor.trimmingCharacters(in: .whitespacesAndNewlines)
        target.credits = credits
        target.colorHex = colorHex
        target.symbolName = symbol
        target.countsTowardGPA = countsTowardGPA
        target.isArchived = isArchived
        target.semester = semesters.first { $0.id == semesterID }
        try? context.save()

        if course == nil, timer.selectedCourseID == nil { timer.selectCourse(target.id) }
        dismiss()
    }

    private func deleteCourse() {
        dismiss()
        onDelete?()
    }
}
