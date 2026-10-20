import SwiftUI
import SwiftData
import KukitCore

/// Create or edit an assignment. Pass `nil` to create (optionally for a given course).
struct AssignmentEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TimerController.self) private var timer
    @Environment(AppRouter.self) private var router
    @Query(sort: \Course.name) private var allCourses: [Course]
    @Query private var linkedSessions: [StudySession]

    var assignment: Assignment?

    @State private var title: String
    @State private var courseID: UUID?
    @State private var type: AssignmentType
    @State private var priority: AssignmentPriority
    @State private var status: AssignmentStatus
    @State private var hasDue: Bool
    @State private var hasTime: Bool
    @State private var dueDate: Date
    @State private var remindersEnabled: Bool
    @State private var useDefaultReminders: Bool
    @State private var customOffsets: Set<Int>
    @State private var details: String
    @State private var addToAppleReminders: Bool
    @State private var addToCalendar: Bool
    @State private var gradeCategoryID: UUID?
    @State private var gradeScore: Double?
    @State private var gradeMax: Double
    @State private var accessMessage: String?
    @State private var confirmDelete = false

    init(assignment: Assignment?, defaultCourseID: UUID? = nil, defaultDue: Date? = nil) {
        self.assignment = assignment
        let id = assignment?.id
        _linkedSessions = Query(filter: #Predicate<StudySession> { $0.assignmentID == id })

        _title = State(initialValue: assignment?.title ?? "")
        _courseID = State(initialValue: assignment?.course?.id ?? defaultCourseID)
        _type = State(initialValue: assignment?.type ?? .homework)
        _priority = State(initialValue: assignment?.priority ?? .normal)
        _status = State(initialValue: assignment?.status ?? .todo)

        let existingDue = assignment?.dueDate ?? defaultDue
        _hasDue = State(initialValue: existingDue != nil)
        _hasTime = State(initialValue: assignment?.hasDueTime ?? false)
        _dueDate = State(initialValue: existingDue ?? Self.defaultDueDate())

        _remindersEnabled = State(initialValue: assignment?.remindersEnabled ?? true)
        _useDefaultReminders = State(initialValue: assignment?.customReminderOffsets == nil)
        _customOffsets = State(initialValue: Set(assignment?.customReminderOffsets ?? [1440]))
        _details = State(initialValue: assignment?.details ?? "")
        _addToAppleReminders = State(initialValue: assignment?.addedToAppleReminders ?? false)
        _addToCalendar = State(initialValue: assignment?.addedToCalendar ?? false)
        _gradeCategoryID = State(initialValue: assignment?.gradeEntry?.category?.id)
        _gradeScore = State(initialValue: assignment?.gradeEntry?.score)
        _gradeMax = State(initialValue: assignment?.gradeEntry?.maxScore ?? 100)
    }

    private static func defaultDueDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: tomorrow) ?? tomorrow
    }

    private var courses: [Course] { allCourses.filter { !$0.isArchived || $0.id == courseID } }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var selectedCourse: Course? { allCourses.first { $0.id == courseID } }
    private var categories: [GradeCategory] { selectedCourse?.sortedCategories ?? [] }
    private var canSave: Bool { !trimmedTitle.isEmpty && courseID != nil }
    private var focusSeconds: TimeInterval { linkedSessions.reduce(0) { $0 + $1.focusSeconds } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Picker("Course", selection: $courseID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(courses) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Type", selection: $type) {
                        ForEach(AssignmentType.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(AssignmentPriority.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(AssignmentStatus.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section("Due") {
                    Toggle("Due date", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                        Toggle("Set a time", isOn: $hasTime.animation())
                        if hasTime {
                            DatePicker("Time", selection: $dueDate, displayedComponents: .hourAndMinute)
                        }
                    }
                }

                if hasDue {
                    Section {
                        Toggle("Remind me", isOn: $remindersEnabled.animation())
                        if remindersEnabled {
                            Toggle("Use default timing", isOn: $useDefaultReminders.animation())
                            if useDefaultReminders {
                                Text(ReminderDefaults.describe(ReminderDefaults.offsets(isExam: type == .exam)))
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                ReminderOffsetPicker(offsets: $customOffsets)
                            }
                        }
                    } header: {
                        Text("Reminders")
                    } footer: {
                        if !hasTime && remindersEnabled {
                            Text("Tasks without a time remind you at \(ReminderDefaults.allDayHour):00.")
                        }
                    }

                    Section {
                        Toggle("Add to Apple Reminders", isOn: $addToAppleReminders)
                            .onChange(of: addToAppleReminders) { _, on in
                                if on { requestRemindersAccess() }
                            }
                        if type == .exam {
                            Toggle("Add to Calendar", isOn: $addToCalendar)
                        }
                        if let accessMessage {
                            Text(accessMessage).font(.footnote).foregroundStyle(.red)
                        }
                    } header: {
                        Text("Other apps")
                    } footer: {
                        Text("One-way: Kukit sends the task to Apple Reminders; changes made there don't come back.\(type == .exam ? " Calendar events are added once and not updated later." : "")")
                    }
                }

                if !categories.isEmpty {
                    Section {
                        Picker("Counts toward", selection: $gradeCategoryID) {
                            Text("Nothing").tag(UUID?.none)
                            ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                        }
                        if gradeCategoryID != nil {
                            HStack {
                                Text("Score")
                                Spacer()
                                TextField("e.g. 18", value: $gradeScore, format: .number)
                                    .multilineTextAlignment(.trailing).frame(width: 80)
                                    #if os(iOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                                Text("/").foregroundStyle(.secondary)
                                TextField("", value: $gradeMax, format: .number)
                                    .multilineTextAlignment(.trailing).frame(width: 80)
                                    #if os(iOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                            }
                        }
                    } header: {
                        Text("Grade")
                    } footer: {
                        Text("The score shows up in \(selectedCourse?.name ?? "the course")'s grades. It counts as a guess until you mark the task done.")
                    }
                }

                if let linked = assignment?.notes, !linked.isEmpty {
                    Section("Linked notes") {
                        ForEach(linked) { note in
                            Label(note.displayTitle, systemImage: "note.text")
                        }
                    }
                }

                Section("Notes") {
                    TextField("Details", text: $details, axis: .vertical)
                        .lineLimit(2...8)
                }

                if let assignment {
                    Section {
                        if focusSeconds > 0 {
                            LabeledContent("Focused so far", value: DurationFormat.short(focusSeconds))
                        }
                        if !assignment.isDone, assignment.course != nil {
                            Button("Focus on this task", systemImage: "timer", action: focus)
                        }
                        Button("Delete task…", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(assignment == nil ? "New task" : "Edit task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let assignment { AssignmentActions.delete(assignment, context: context) }
                    dismiss()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 640)
        #endif
    }

    // MARK: Actions

    private func saveGrade(for target: Assignment) {
        guard let category = categories.first(where: { $0.id == gradeCategoryID }) else {
            if let existing = target.gradeEntry {
                context.delete(existing)
                target.gradeEntry = nil
            }
            return
        }
        guard let score = gradeScore, gradeMax > 0 else { return }
        let entry: GradeEntry
        if let existing = target.gradeEntry {
            entry = existing
        } else {
            entry = GradeEntry(name: trimmedTitle, score: score, maxScore: gradeMax, category: category)
            context.insert(entry)
            target.gradeEntry = entry
        }
        entry.name = trimmedTitle
        entry.category = category
        entry.score = score
        entry.maxScore = gradeMax
        entry.isPlanned = !target.isDone
        entry.date = target.completedAt ?? .now
    }

    private func requestRemindersAccess() {
        Task {
            let granted = await EventKitService.shared.requestRemindersAccess()
            if granted {
                accessMessage = nil
            } else {
                addToAppleReminders = false
                accessMessage = "Kukit doesn't have access to Reminders. Allow it in system Settings ▸ Privacy ▸ Reminders."
            }
        }
    }

    private func focus() {
        guard let assignment, let course = assignment.course else { return }
        timer.selectCourse(course.id)
        timer.selectAssignment(assignment.id)
        router.section = .focus
        dismiss()
    }

    private func save() {
        guard let course = allCourses.first(where: { $0.id == courseID }) else { return }
        let target: Assignment
        if let assignment {
            target = assignment
        } else {
            target = Assignment(title: trimmedTitle, course: course)
            context.insert(target)
        }

        let wasOnReminders = target.addedToAppleReminders
        let wasOnCalendar = target.addedToCalendar

        target.title = trimmedTitle
        target.course = course
        target.type = type
        target.priority = priority
        target.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        target.status = status

        if hasDue {
            target.hasDueTime = hasTime
            target.dueDate = hasTime ? dueDate : Calendar.current.startOfDay(for: dueDate)
        } else {
            target.dueDate = nil
            target.hasDueTime = false
        }

        saveGrade(for: target)

        target.remindersEnabled = hasDue && remindersEnabled
        target.customReminderOffsets = useDefaultReminders ? nil : customOffsets.sorted(by: >)
        target.addedToAppleReminders = addToAppleReminders
        target.addedToCalendar = type == .exam && addToCalendar

        AssignmentActions.persist(
            target, context: context,
            createReminder: addToAppleReminders && !wasOnReminders,
            createCalendarEvent: target.addedToCalendar && !wasOnCalendar
        )
        dismiss()
    }
}
