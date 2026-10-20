import SwiftUI
import SwiftData
import KukitCore

struct CoursesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \Semester.startDate, order: .reverse) private var semesters: [Semester]
    @State private var showingNew = false
    @State private var showArchived = false

    private var active: [Course] { courses.filter { !$0.isArchived } }
    private var archived: [Course] { courses.filter(\.isArchived) }

    private struct Group: Identifiable {
        var id: String
        var title: String
        var courses: [Course]
    }

    /// Active courses grouped by semester (newest first), then those without a semester.
    private var groups: [Group] {
        var result: [Group] = semesters.compactMap { semester in
            let inSemester = active.filter { $0.semester?.id == semester.id }
            return inSemester.isEmpty ? nil : Group(id: semester.id.uuidString, title: semester.name, courses: inSemester)
        }
        let loose = active.filter { $0.semester == nil }
        if !loose.isEmpty {
            result.append(Group(id: "none", title: result.isEmpty ? "Courses" : "No semester", courses: loose))
        }
        return result
    }

    var body: some View {
        List {
            if courses.isEmpty {
                EmptyStateView(
                    systemImage: "books.vertical",
                    title: "No courses yet",
                    message: "Add the courses you're taking this semester. Focus time, grades and tasks will hang off them.",
                    actionTitle: "Add a course"
                ) { showingNew = true }
                .listRowBackground(Color.clear)
            }

            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.courses) { course in
                        NavigationLink(value: course) { CourseRow(course: course) }
                    }
                }
            }

            if !archived.isEmpty {
                Section {
                    DisclosureGroup("Archived (\(archived.count))", isExpanded: $showArchived) {
                        ForEach(archived) { course in
                            NavigationLink(value: course) { CourseRow(course: course) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Courses")
        .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add course", systemImage: "plus") { showingNew = true }
            }
        }
        .sheet(isPresented: $showingNew) { CourseEditorView(course: nil) }
    }
}

struct CourseRow: View {
    var course: Course

    private var weekSeconds: TimeInterval {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return (course.sessions ?? []).filter { $0.startedAt >= start }.reduce(0) { $0 + $1.focusSeconds }
    }

    var body: some View {
        HStack(spacing: 12) {
            CourseBadge(color: course.color, symbol: course.symbolName)
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if weekSeconds > 0 {
                Text(DurationFormat.short(weekSeconds))
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let credits = course.credits.formatted(.number.precision(.fractionLength(0...1)))
        return [course.code.isEmpty ? nil : course.code, "\(credits) credits"]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
