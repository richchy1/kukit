import SwiftUI
import SwiftData
import KukitCore

/// Your courses as colorful workspaces.
struct CoursesView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
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
            result.append(Group(id: "none", title: result.isEmpty ? "This semester" : "No semester", courses: loose))
        }
        return result
    }

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if courses.isEmpty {
                    EmptyStateView(
                        mood: .idle, title: "An empty pantry",
                        message: Chef.line(.emptyCourses, seed: Chef.daySeed()),
                        actionTitle: "Add your first course"
                    ) { showingNew = true }
                    .card(padding: 24, tone: .soft)
                }

                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(group.title, systemImage: "books.vertical.fill")
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(group.courses) { course in
                                NavigationLink(value: course) { CourseCard(course: course) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !archived.isEmpty {
                    DisclosureGroup(isExpanded: $showArchived) {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(archived) { course in
                                NavigationLink(value: course) { CourseCard(course: course) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Archived (\(archived.count))").font(.kukit(.headline, weight: .bold))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .kukitScreen()
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

/// One course workspace: its color, what you've studied, how the tasks are going, the grade,
/// and a one-tap way to start cooking.
struct CourseCard: View {
    var course: Course
    @Environment(TimerController.self) private var timer
    @Environment(AppRouter.self) private var router
    @Query(sort: \GradingScale.createdAt) private var scales: [GradingScale]
    @Query(sort: [SortDescriptor(\TimerPreset.sortOrder), SortDescriptor(\TimerPreset.createdAt)])
    private var presets: [TimerPreset]

    private var weekSeconds: TimeInterval {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return (course.sessions ?? []).filter { $0.startedAt >= start }.reduce(0) { $0 + $1.focusSeconds }
    }

    private var taskProgress: (done: Int, total: Int) {
        let items = course.assignments ?? []
        return (items.filter(\.isDone).count, items.count)
    }

    var body: some View {
        let grade = course.gradeSummary
        let scale = GradingScales.resolve(for: course, in: scales)
        let band = grade.currentPercent.flatMap { scale.band(for: $0) }
        let (done, total) = taskProgress

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CourseBadge(color: course.color, symbol: course.symbolName, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name).font(.kukit(.headline, weight: .heavy)).lineLimit(2)
                    Text(subtitle).font(.kukit(.caption, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let band, let percent = grade.currentPercent {
                    VStack(spacing: 0) {
                        Text(band.label).font(.kukit(.title3, weight: .heavy)).foregroundStyle(course.color)
                        Text(GradeFormat.percent(percent)).font(.kukit(.caption2, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Grade \(band.label), \(GradeFormat.percent(percent))")
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("This week", systemImage: "clock.fill")
                        .font(.kukit(.caption2, weight: .semibold)).foregroundStyle(.secondary)
                    Text(weekSeconds > 0 ? DurationFormat.short(weekSeconds) : "–")
                        .font(.kukit(.subheadline, weight: .heavy)).monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(total == 0 ? "No tasks yet" : "\(done) of \(total) tasks", systemImage: "fork.knife")
                        .font(.kukit(.caption2, weight: .semibold)).foregroundStyle(.secondary)
                    RecipeBar(progress: total == 0 ? 0 : Double(done) / Double(total), tint: course.color, height: 8)
                }
            }

            if !course.isArchived {
                Button {
                    Haptics.play(.heavy)
                    timer.selectCourse(course.id)
                    timer.start(config: PresetCatalog.resolve(id: timer.selectedPresetID, custom: presets))
                    router.section = .focus
                } label: {
                    Label("Start Cooking", systemImage: "flame.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.kukit(.secondary, tint: course.color))
                .disabled(timer.state.isActive)
            }
        }
        .card(padding: 16)
        .overlay(alignment: .topLeading) {
            // A folder-tab of the course color.
            UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                .fill(course.color)
                .frame(width: 54, height: 6)
                .padding(.leading, 20)
        }
        .hoverHighlight(radius: Theme.cardRadius)
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String {
        let credits = course.credits.formatted(.number.precision(.fractionLength(0...1)))
        return [course.code.isEmpty ? nil : course.code, "\(credits) credits", course.semester?.name]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
