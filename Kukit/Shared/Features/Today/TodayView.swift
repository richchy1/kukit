import SwiftUI
import SwiftData
import Charts
import KukitCore

/// "What's cooking today?": the timer, today's tasks, a suggested order for your courses and how
/// the day is going. Two columns on a wide window, one on iPhone.
struct TodayView: View {
    @Environment(TimerController.self) private var timer
    @Environment(AppRouter.self) private var router

    @Query(sort: \StudySession.startedAt) private var sessions: [StudySession]
    @Query(sort: \Course.name) private var allCourses: [Course]
    @Query private var assignments: [Assignment]
    @Query(sort: [SortDescriptor(\TimerPreset.sortOrder), SortDescriptor(\TimerPreset.createdAt)])
    private var customPresets: [TimerPreset]
    @AppStorage(Prefs.dailyGoalMinutes) private var goalMinutes = 120

    @State private var editing: Assignment?
    @State private var showNewTask = false
    @State private var isWide = false
    #if os(iOS)
    @State private var destination: MoreDestination?
    #endif

    private let calculator = StatsCalculator()

    // MARK: Derived data

    private var courses: [Course] { allCourses.filter { !$0.isArchived } }
    private var summaries: [SessionSummary] { sessions.map(\.summary) }
    private var todaySeconds: TimeInterval { calculator.total(summaries, on: .now) }
    private var goalSeconds: TimeInterval { TimeInterval(goalMinutes * 60) }
    private var goalReached: Bool { goalSeconds > 0 && todaySeconds >= goalSeconds }
    private var week: [DayTotal] { calculator.dailyTotals(summaries, endingOn: .now, days: 7) }
    private var streak: Int { calculator.currentStreak(summaries, goalSeconds: goalSeconds, asOf: .now) }

    /// Open tasks that are overdue or due within the next three days.
    private var dueSoon: [Assignment] {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: 4, to: calendar.startOfDay(for: .now)) ?? .now
        return Assignment.sortedByUrgency(assignments.filter { item in
            guard !item.isDone, let due = item.dueDate else { return false }
            return due < horizon
        })
    }

    private var tasksDoneToday: Int {
        assignments.filter { $0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false }.count
    }

    private var nextExam: Assignment? {
        let today = Calendar.current.startOfDay(for: .now)
        return assignments
            .filter { $0.type == .exam && !$0.isDone && ($0.dueDate ?? .distantPast) >= today }
            .min { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var selectedConfig: TimerConfig {
        PresetCatalog.resolve(id: timer.selectedPresetID, custom: customPresets)
    }

    private struct RecipeItem: Identifiable {
        var course: Course
        var nextDue: Date?
        var dueSoon: Int
        var weekSeconds: TimeInterval
        var id: UUID { course.id }
    }

    /// Courses in a sensible cooking order: soonest deadline first, then least studied this week.
    private var recipe: [RecipeItem] {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let items = courses.map { course -> RecipeItem in
            let open = (course.assignments ?? []).filter { !$0.isDone }
            let nextDue = open.compactMap(\.dueDate).min()
            let soonCount = open.filter { $0.dueBucket != .later && $0.dueBucket != .noDate }.count
            let studied = (course.sessions ?? []).filter { $0.startedAt >= weekStart }.reduce(0) { $0 + $1.focusSeconds }
            return RecipeItem(course: course, nextDue: nextDue, dueSoon: soonCount, weekSeconds: studied)
        }
        return items.sorted { a, b in
            switch (a.nextDue, b.nextDue) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.weekSeconds < b.weekSeconds
            }
        }
    }

    private var headerMood: ChefMood {
        let state = timer.state
        if state.status == .running { return state.phase.isBreak ? .breakTime : .working }
        if goalReached { return .goalDone }
        if dueSoon.isEmpty && todaySeconds == 0 { return .noTasks }
        return .idle
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                // One layout at a time: ViewThatFits would build the timer card twice.
                if isWide {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 20) { FocusCard(style: .compact); recipeCard }
                            .frame(maxWidth: 440)
                        VStack(spacing: 20) { ingredientsCard; progressCard }
                    }
                } else {
                    VStack(spacing: 20) { FocusCard(style: .compact); ingredientsCard; recipeCard; progressCard }
                }
            }
            .padding(20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { isWide = $0 >= 760 }
        .kukitScreen()
        .navigationTitle("Today")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editing) { AssignmentEditorView(assignment: $0) }
        .sheet(isPresented: $showNewTask) {
            AssignmentEditorView(assignment: nil, defaultCourseID: timer.selectedCourseID)
        }
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

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill").foregroundStyle(Theme.accent)
                    Text("KUKIT")
                        .font(.kukit(.caption, weight: .heavy))
                        .tracking(2.5)
                        .foregroundStyle(Theme.accentText)
                }
                Text(greeting)
                    .font(.kukit(.title, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { dateText; progressPill }
                    VStack(alignment: .leading, spacing: 6) { dateText; progressPill }
                }
            }
            Spacer(minLength: 0)
            ChefKukit(mood: headerMood, size: 92)
        }
    }

    private var dateText: some View {
        Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
            .font(.kukit(.subheadline, weight: .medium))
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private var greeting: String {
        let seed = Chef.daySeed()
        if goalReached { return Chef.line(.goalComplete, seed: seed) }
        return Chef.line(ChefContext.dashboard(hour: Calendar.current.component(.hour, from: .now)), seed: seed)
    }

    private var progressPill: some View {
        HStack(spacing: 6) {
            Image(systemName: goalReached ? "checkmark.seal.fill" : "clock.fill")
                .foregroundStyle(goalReached ? Theme.basil : Theme.accent)
                .imageScale(.small)
            Text("\(DurationFormat.short(todaySeconds)) of \(DurationFormat.short(goalSeconds))")
                .font(.kukit(.caption, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            RecipeBar(progress: goalSeconds > 0 ? todaySeconds / goalSeconds : 0,
                      tint: goalReached ? Theme.basil : Theme.accent, height: 6)
                .frame(width: 44)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.softBackground.opacity(0.55), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today: \(DurationFormat.short(todaySeconds)) of \(DurationFormat.short(goalSeconds)) goal")
    }

    // MARK: Today's ingredients

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Today's ingredients", systemImage: "fork.knife")
                Button("All tasks") { router.section = .tasks }
                    .buttonStyle(.kukit(.ghost))
            }

            if let exam = nextExam, let due = exam.dueDate { examBanner(exam, due: due) }

            if dueSoon.isEmpty {
                EmptyStateView(
                    mood: .noTasks, title: "Nothing on the menu",
                    message: courses.isEmpty
                        ? Chef.line(.emptyCourses, seed: Chef.daySeed())
                        : Chef.line(.emptyTasks, seed: Chef.daySeed()),
                    actionTitle: courses.isEmpty ? "Add a course" : "Add a task"
                ) {
                    if courses.isEmpty { router.section = .courses } else { showNewTask = true }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(dueSoon.prefix(6)) { item in
                        AssignmentRow(assignment: item) { editing = item }
                            .padding(.vertical, 8)
                        if item.id != dueSoon.prefix(6).last?.id { Divider().opacity(0.6) }
                    }
                }
                if dueSoon.count > 6 {
                    Text("+ \(dueSoon.count - 6) more in Tasks")
                        .font(.kukit(.footnote, weight: .semibold)).foregroundStyle(.secondary)
                }
            }

            if !courses.isEmpty {
                Divider().opacity(0.6)
                QuickAddRow(courses: courses, defaultCourseID: timer.selectedCourseID)
            }
        }
        .card(padding: 18)
    }

    private func examBanner(_ exam: Assignment, due: Date) -> some View {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: due)).day ?? 0
        return Button { editing = exam } label: {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text("\(days)").font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text(days == 1 ? "day" : "days").font(.kukit(.caption2, weight: .semibold))
                }
                .frame(width: 52)
                .foregroundStyle(days <= 2 ? Theme.accentText : Theme.ink)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next exam").font(.kukit(.caption, weight: .semibold)).foregroundStyle(.secondary)
                    Text(exam.title).font(.kukit(.subheadline, weight: .heavy))
                    Text([exam.course?.name, exam.dueDescription].compactMap { $0 }.joined(separator: " · "))
                        .font(.kukit(.caption, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "graduationcap.fill").foregroundStyle(exam.course?.color ?? Theme.accent)
            }
            .padding(10)
            .background(Theme.softBackgroundFaint, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the exam")
    }

    // MARK: Today's recipe

    private var recipeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Today's recipe", systemImage: "list.bullet.clipboard")
            if recipe.isEmpty {
                Text("Add a course and your cooking order shows up here.")
                    .font(.kukit(.subheadline, weight: .medium)).foregroundStyle(.secondary)
            } else {
                Text("Suggested order: deadlines first.")
                    .font(.kukit(.footnote, weight: .medium)).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(recipe.prefix(4).enumerated()), id: \.element.id) { index, item in
                        recipeRow(item, step: index + 1)
                            .padding(.vertical, 8)
                        if index < min(recipe.count, 4) - 1 { Divider().opacity(0.6) }
                    }
                }
            }
        }
        .card(padding: 18)
    }

    private func recipeRow(_ item: RecipeItem, step: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(step)")
                .font(.kukit(.caption, weight: .heavy))
                .foregroundStyle(item.course.color)
                .frame(width: 22, height: 22)
                .background(item.course.color.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            CourseBadge(color: item.course.color, symbol: item.course.symbolName, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.course.name).font(.kukit(.subheadline, weight: .bold)).lineLimit(1)
                Text(recipeDetail(item)).font(.kukit(.caption, weight: .medium)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button {
                Haptics.play(.heavy)
                timer.selectCourse(item.course.id)
                timer.start(config: selectedConfig)
            } label: {
                Label("Cook", systemImage: "play.fill")
            }
            .buttonStyle(.kukit(.secondary))
            .controlSize(.small)
            .disabled(timer.state.isActive)
            .accessibilityLabel("Start cooking \(item.course.name)")
        }
    }

    private func recipeDetail(_ item: RecipeItem) -> String {
        var parts: [String] = []
        if item.dueSoon > 0 { parts.append("\(item.dueSoon) due soon") }
        parts.append(item.weekSeconds > 0 ? "\(DurationFormat.short(item.weekSeconds)) this week" : "not studied this week")
        return parts.joined(separator: " · ")
    }

    // MARK: Daily progress

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Daily progress", systemImage: "chart.bar.fill")

            HStack(spacing: 16) {
                ProgressRing(progress: goalSeconds > 0 ? todaySeconds / goalSeconds : 0,
                             tint: goalReached ? Theme.basil : Theme.accent, lineWidth: 11) {
                    if goalReached {
                        Image(systemName: "star.fill").foregroundStyle(Theme.butter).font(.title3)
                    } else {
                        Text("\(Int(min(1, goalSeconds > 0 ? todaySeconds / goalSeconds : 0) * 100))%")
                            .font(.kukit(.subheadline, weight: .heavy)).monospacedDigit()
                    }
                }
                .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Studied today").font(.kukit(.caption, weight: .semibold)).foregroundStyle(.secondary)
                    Text(DurationFormat.short(todaySeconds))
                        .font(.kukit(.largeTitle, weight: .heavy)).monospacedDigit()
                    Text(goalReached ? Chef.line(.goalComplete, seed: Chef.daySeed() + 1) : "Goal \(DurationFormat.short(goalSeconds))")
                        .font(.kukit(.footnote, weight: .semibold))
                        .foregroundStyle(goalReached ? Theme.basilText : Color.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                StatTile(title: "Streak", value: streak == 1 ? "1 day" : "\(streak) days",
                         systemImage: "flame.fill", tint: streak > 0 ? Theme.accentText : Theme.ink)
                StatTile(title: "Tasks done", value: "\(tasksDoneToday)",
                         systemImage: "checkmark.circle.fill", tint: tasksDoneToday > 0 ? Theme.basilText : Theme.ink)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("This week").font(.kukit(.subheadline, weight: .bold))
                    Spacer()
                    Text(DurationFormat.short(week.reduce(0) { $0 + $1.seconds }))
                        .font(.kukit(.footnote, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
                }
                Chart(week) { item in
                    BarMark(x: .value("Day", item.day, unit: .day), y: .value("Minutes", item.seconds / 60))
                        .foregroundStyle(barColor(item))
                        .cornerRadius(5)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 100)
                .accessibilityLabel("Focus time over the last 7 days")
            }
        }
        .card(padding: 18)
    }

    private func barColor(_ item: DayTotal) -> Color {
        if Calendar.current.isDateInToday(item.day) { return Theme.accent }
        if goalSeconds > 0, item.seconds >= goalSeconds { return Theme.basil }
        return Theme.softBackground
    }
}

#if os(iOS)
/// Screens that don't have their own tab on iPhone; reached from the menu on Today.
enum MoreDestination: Hashable, Identifiable {
    case grades, stats, settings
    var id: Self { self }
}
#endif
