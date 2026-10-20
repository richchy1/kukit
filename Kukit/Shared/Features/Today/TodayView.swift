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
    @AppStorage(Prefs.dailyGoalMinutes) private var goalMinutes = 120

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                greeting
                focusCard
                goalCard
                weekCard
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.screenBackground)
        .navigationTitle("Today")
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
