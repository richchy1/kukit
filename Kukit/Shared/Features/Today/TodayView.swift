import SwiftUI
import SwiftData
import Charts
import KukitCore

struct TodayView: View {
    @Environment(TimerController.self) private var timer
    @Environment(AppRouter.self) private var router

    @Query(sort: \StudySession.startedAt) private var sessions: [StudySession]
    @Query(sort: \Course.name) private var allCourses: [Course]
    @Query(sort: [SortDescriptor(\TimerPreset.sortOrder), SortDescriptor(\TimerPreset.createdAt)])
    private var customPresets: [TimerPreset]
    @Query private var assignments: [Assignment]
    @Query(sort: \GradingScale.createdAt) private var scales: [GradingScale]
    @AppStorage(Prefs.dailyGoalMinutes) private var goalMinutes = 120
    @State private var editing: Assignment?
    #if os(iOS)
    @State private var destination: MoreDestination?
    #endif

    private let calculator = StatsCalculator()

    private var courses: [Course] { allCourses.filter { !$0.isArchived } }
    private var summaries: [SessionSummary] { sessions.map(\.summary) }
    private var todaySeconds: TimeInterval { calculator.total(summaries, on: .now) }
    private var goalSeconds: TimeInterval { TimeInterval(goalMinutes * 60) }
    private var week: [DayTotal] { calculator.dailyTotals(summaries, endingOn: .now, days: 7) }
    private var streak: Int { calculator.currentStreak(summaries, goalSeconds: goalSeconds, asOf: .now) }
    private var configs: [TimerConfig] { PresetCatalog.all(custom: customPresets) }
    private var selectedConfig: TimerConfig {
        PresetCatalog.resolve(id: timer.selectedPresetID, custom: customPresets)
    }
    private var selectedCourse: Course? { allCourses.first { $0.id == timer.selectedCourseID } }

    /// Open tasks that are overdue or due within the next three days.
    private var dueSoon: [Assignment] {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: 4, to: calendar.startOfDay(for: .now)) ?? .now
        let soon = assignments.filter { item in
            guard !item.isDone, let due = item.dueDate else { return false }
            return due < horizon
        }
        return Assignment.sortedByUrgency(soon)
    }

    private var nextExam: Assignment? {
        let today = Calendar.current.startOfDay(for: .now)
        return assignments
            .filter { $0.type == .exam && !$0.isDone && ($0.dueDate ?? .distantPast) >= today }
            .min { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                greeting
                focusCard
                dueSoonCard
                examCard
                gradeCard
                goalCard
                weekCard
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.screenBackground)
        .navigationTitle("Today")
        .sheet(item: $editing) { AssignmentEditorView(assignment: $0) }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Grades & GPA", systemImage: AppSection.grades.systemImage) { destination = .grades }
                    Button("Stats", systemImage: AppSection.stats.systemImage) { destination = .stats }
                    Button("Settings", systemImage: AppSection.settings.systemImage) { destination = .settings }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(item: $destination) { target in
            switch target {
            case .grades: GradesOverviewView()
            case .stats: StatsView()
            case .settings: SettingsView()
            }
        }
        #endif
    }

    // MARK: Cards

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greetingText).font(.title2.weight(.semibold))
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        case 18..<23: "Good evening"
        default: "Burning the midnight oil?"
        }
    }

    @ViewBuilder
    private var focusCard: some View {
        if timer.state.isActive {
            Button { router.section = .focus } label: {
                HStack(spacing: 16) {
                    TimerRingView(
                        idleConfig: timer.state.config,
                        courseColor: allCourses.first { $0.id == timer.state.context.courseID }?.color,
                        digitSize: 22, lineWidth: 8, showsSubtitle: false
                    )
                    .frame(width: 104, height: 104)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(timer.state.subtitle).font(.headline)
                        Text(allCourses.first { $0.id == timer.state.context.courseID }?.name ?? "")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Tap to open").font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .card()
            }
            .buttonStyle(.plain)
        } else if courses.isEmpty {
            EmptyStateView(
                systemImage: "books.vertical",
                title: "Welcome to Kukit",
                message: "Add your first course, then start a focus session to cook through your semester.",
                actionTitle: "Add a course"
            ) { router.section = .courses }
            .card()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ready to cook?").font(.headline)
                CoursePickerMenu(courses: courses, selectedID: timer.selectedCourseID) { timer.selectCourse($0) }
                HStack(spacing: 12) {
                    Menu {
                        ForEach(configs) { config in
                            Button { timer.selectPreset(config) } label: {
                                if config.id == selectedConfig.id {
                                    Label("\(config.name) · \(config.summary)", systemImage: "checkmark")
                                } else {
                                    Text("\(config.name) · \(config.summary)")
                                }
                            }
                        }
                    } label: {
                        Label(selectedConfig.name, systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        timer.start(config: selectedConfig)
                        router.section = .focus
                    } label: {
                        Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(selectedCourse?.color ?? Theme.accent)
                    .disabled(selectedCourse == nil)
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private var dueSoonCard: some View {
        if !dueSoon.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Due soon").font(.headline)
                    Spacer()
                    Button("All tasks") { router.section = .tasks }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                }
                ForEach(dueSoon.prefix(5)) { item in
                    AssignmentRow(assignment: item) { editing = item }
                    if item.id != dueSoon.prefix(5).last?.id { Divider() }
                }
                if dueSoon.count > 5 {
                    Text("+ \(dueSoon.count - 5) more")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private var examCard: some View {
        if let exam = nextExam, let due = exam.dueDate {
            let days = Calendar.current.dateComponents(
                [.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: due)
            ).day ?? 0
            Button { editing = exam } label: {
                HStack(spacing: 14) {
                    VStack(spacing: 0) {
                        Text("\(days)").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(days == 1 ? "day" : "days").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(width: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next exam").font(.caption).foregroundStyle(.secondary)
                        Text(exam.title).font(.headline)
                        Text([exam.course?.name, exam.dueDescription].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "graduationcap.fill").foregroundStyle(exam.course?.color ?? Theme.accent)
                }
                .contentShape(Rectangle())
                .card()
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var gradeCard: some View {
        let graded = courses.filter { $0.hasGrades && $0.gradeSummary.currentPercent != nil }
        if !graded.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Grades").font(.headline)
                    Spacer()
                    #if os(macOS)
                    Button("All grades") { router.section = .grades }
                        .font(.subheadline).buttonStyle(.borderless)
                    #endif
                }
                ForEach(graded.prefix(5)) { course in
                    let summary = course.gradeSummary
                    let band = summary.currentPercent.flatMap { GradingScales.resolve(for: course, in: scales).band(for: $0) }
                    HStack(spacing: 10) {
                        CourseBadge(color: course.color, symbol: course.symbolName, size: 26)
                        Text(course.name).font(.subheadline)
                        Spacer()
                        Text(GradeFormat.percent(summary.currentPercent)).monospacedDigit().foregroundStyle(.secondary)
                        if let band {
                            Text(band.label).font(.subheadline.weight(.bold)).foregroundStyle(course.color)
                                .frame(minWidth: 28, alignment: .trailing)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .card()
        }
    }

    private var goalCard: some View {
        HStack(spacing: 18) {
            ProgressRing(progress: goalSeconds > 0 ? todaySeconds / goalSeconds : 0, tint: Theme.accent, lineWidth: 10) {
                Text(goalSeconds > 0 ? "\(Int(min(1, todaySeconds / goalSeconds) * 100))%" : "–")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 6) {
                Text("Today").font(.caption).foregroundStyle(.secondary)
                Text(DurationFormat.short(todaySeconds))
                    .font(.title.weight(.semibold)).monospacedDigit()
                Text("Goal \(DurationFormat.short(goalSeconds))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 2) {
                Image(systemName: "flame.fill").font(.title2).foregroundStyle(streak > 0 ? .orange : .secondary)
                Text("\(streak)").font(.title3.weight(.semibold)).monospacedDigit()
                Text(streak == 1 ? "day" : "days").font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Streak \(streak) day\(streak == 1 ? "" : "s")")
        }
        .card()
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This week").font(.headline)
                Spacer()
                Text(DurationFormat.short(week.reduce(0) { $0 + $1.seconds }))
                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            Chart(week) { item in
                BarMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Minutes", item.seconds / 60)
                )
                .foregroundStyle(Calendar.current.isDateInToday(item.day) ? Theme.accent : Theme.accent.opacity(0.45))
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 110)
            .accessibilityLabel("Focus time over the last 7 days")
        }
        .card()
    }
}

#if os(iOS)
/// Screens that don't have their own tab on iPhone; reached from the menu on Today.
enum MoreDestination: Hashable, Identifiable {
    case grades, stats, settings
    var id: Self { self }
}
#endif
