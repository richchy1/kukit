import SwiftUI
import SwiftData
import KukitCore

struct GradeCategoryEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var course: Course
    var category: GradeCategory?

    @State private var name: String
    @State private var weight: Double
    @State private var method: CategoryMethod
    @State private var confirmDelete = false

    init(course: Course, category: GradeCategory?) {
        self.course = course
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _weight = State(initialValue: category?.weight ?? 10)
        _method = State(initialValue: category?.method ?? .totalPoints)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Midterm)", text: $name)
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("", value: $weight, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("%").foregroundStyle(.secondary)
                    }
                }
                Section {
                    Picker("How scores combine", selection: $method) {
                        Text("Total points").tag(CategoryMethod.totalPoints)
                        Text("Average of percentages").tag(CategoryMethod.averageOfPercentages)
                    }
                } footer: {
                    Text(method == .totalPoints
                         ? "Adds up all points earned and divides by all points possible, so bigger assignments count for more."
                         : "Averages each score's percentage, so every score counts equally.")
                }
                if category != nil {
                    Section {
                        Button("Delete category…", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(category == nil ? "New category" : "Edit category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(trimmed.isEmpty || weight < 0)
                }
            }
            .confirmationDialog("Delete \(category?.name ?? "category")?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete category and its scores", role: .destructive) {
                    if let category { context.delete(category); try? context.save() }
                    dismiss()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
    }

    private func save() {
        let target: GradeCategory
        if let category {
            target = category
        } else {
            target = GradeCategory(name: trimmed, weight: weight, sortOrder: course.gradeCategories?.count ?? 0, course: course)
            context.insert(target)
        }
        target.name = trimmed
        target.weight = max(0, weight)
        target.method = method
        try? context.save()
        dismiss()
    }
}

struct GradeEntryEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var course: Course
    var entry: GradeEntry?

    @State private var name: String
    @State private var categoryID: UUID?
    @State private var score: Double
    @State private var maxScore: Double
    @State private var isPlanned: Bool
    @State private var date: Date
    @State private var assignmentID: UUID?

    init(course: Course, entry: GradeEntry?, defaultCategory: GradeCategory?) {
        self.course = course
        self.entry = entry
        _name = State(initialValue: entry?.name ?? "")
        _categoryID = State(initialValue: entry?.category?.id ?? defaultCategory?.id ?? course.sortedCategories.first?.id)
        _score = State(initialValue: entry?.score ?? 0)
        _maxScore = State(initialValue: entry?.maxScore ?? 100)
        _isPlanned = State(initialValue: entry?.isPlanned ?? false)
        _date = State(initialValue: entry?.date ?? .now)
        _assignmentID = State(initialValue: entry?.assignment?.id)
    }

    private var openOrLinkedAssignments: [Assignment] {
        (course.assignments ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    private var percentText: String {
        maxScore > 0 ? GradeFormat.percent(score * 100 / maxScore) : "–"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Midterm exam)", text: $name)
                    Picker("Category", selection: $categoryID) {
                        ForEach(course.sortedCategories) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section {
                    HStack {
                        Text("Score")
                        Spacer()
                        TextField("", value: $score, format: .number)
                            .multilineTextAlignment(.trailing).frame(width: 80)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("/").foregroundStyle(.secondary)
                        TextField("", value: $maxScore, format: .number)
                            .multilineTextAlignment(.trailing).frame(width: 80)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    LabeledContent("Percent", value: percentText)
                    Toggle("Not graded yet — this is my guess", isOn: $isPlanned)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                if !openOrLinkedAssignments.isEmpty {
                    Section {
                        Picker("Linked task", selection: $assignmentID) {
                            Text("None").tag(UUID?.none)
                            ForEach(openOrLinkedAssignments) { Text($0.title).tag(Optional($0.id)) }
                        }
                    }
                }
                if entry != nil {
                    Section {
                        Button("Delete score", role: .destructive) {
                            if let entry { context.delete(entry); try? context.save() }
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(entry == nil ? "New score" : "Edit score")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(categoryID == nil || maxScore <= 0)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 520)
        #endif
    }

    private func save() {
        guard let category = course.sortedCategories.first(where: { $0.id == categoryID }) else { return }
        let target: GradeEntry
        if let entry {
            target = entry
        } else {
            target = GradeEntry(name: name, score: score, maxScore: maxScore, category: category)
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.category = category
        target.score = score
        target.maxScore = maxScore
        target.isPlanned = isPlanned
        target.date = date
        target.assignment = openOrLinkedAssignments.first { $0.id == assignmentID }
        try? context.save()
        dismiss()
    }
}
