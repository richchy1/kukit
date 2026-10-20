import SwiftUI
import SwiftData
import Charts
import KukitCore

struct StatsView: View {
    @Query(sort: \StudySession.startedAt) private var sessions: [StudySession]
    @Query private var courses: [Course]
    @AppStorage(Prefs.dailyGoalMinutes) private var goalMinutes = 120
    @State private var range: StatsRange = .week

    enum StatsRange: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    private let calculator = StatsCalculator()

    private var summaries: [SessionSummary] { sessions.map(\.summary) }
    private var goalSeconds: TimeInterval { TimeInterval(goalMinutes * 60) }
    private var daily: [DayTotal] { calculator.dailyTotals(summaries, endingOn: .now, days: range.days) }
    private var totalSeconds: TimeInterval { daily.reduce(0) { $0 + $1.seconds } }
    private var bestDay: DayTotal? { daily.max { $0.seconds < $1.seconds } }
    private var rangeStart: Date { daily.first?.day ?? .now }
    private var todaySeconds: TimeInterval { calculator.total(summaries, on: .now) }
    private var streak: Int { calculator.currentStreak(summaries, goalSeconds: goalSeconds, asOf: .now) }

    private var byCourse: [CourseTotal] {
        calculator.courseTotals(summaries, from: rangeStart, to: .distantFuture)
    }

    private var achievements: [Achievement] {
        Achievements.evaluate(summaries, goalSeconds: goalSeconds, now: .now)
    }

    private var celebration: (mood: ChefMood, line: String)? {
        let seed = Chef.daySeed()
        if Achievements.isRecordToday(summaries, now: .now) { return (.celebrate, Chef.line(.recordDay, seed: seed)) }
        if goalSeconds > 0, todaySeconds >= goalSeconds { return (.goalDone, Chef.line(.goalComplete, seed: seed)) }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if sessions.isEmpty {
                    EmptyStateView(
                        mood: .idle, title: "The cookbook is empty",
                        message: Chef.line(.emptyHistory, seed: Chef.daySeed())
                    )
                    .card(padding: 20, tone: .soft)
                } else if let celebration {
                    HStack(spacing: 14) {
                        ChefKukit(mood: celebration.mood, size: 78)
                        Text(celebration.line).font(.kukit(.headline, weight: .heavy))
                        Spacer(minLength: 0)
                    }
                    .card(padding: 14, tone: .success)
                }

                Picker("Range", selection: $range) {
                    ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    StatTile(title: "Total focus", value: DurationFormat.short(totalSeconds), systemImage: "clock.fill", tint: Theme.accentText)
                    StatTile(title: "Daily average", value: DurationFormat.short(totalSeconds / Double(range.days)), systemImage: "chart.line.uptrend.xyaxis")
                    StatTile(title: "Best day", value: bestDay.map { DurationFormat.short($0.seconds) } ?? "–", systemImage: "trophy.fill")
                    StatTile(title: "Streak", value: streak == 1 ? "1 day" : "\(streak) days", systemImage: "flame.fill", tint: streak > 0 ? Theme.accentText : Theme.ink)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Focus per day", systemImage: "chart.bar.fill")
                    dailyChart.frame(height: 200)
                }
                .card(padding: 18)

                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle("By course", systemImage: "books.vertical.fill")
                    if byCourse.isEmpty {
                        Text("Nothing cooked in this period.")
                            .font(.kukit(.subheadline, weight: .medium)).foregroundStyle(.secondary)
                    }
                    ForEach(byCourse) { entry in courseBar(entry) }
                }
                .card(padding: 18)

                achievementsCard

                NavigationLink {
                    HistoryView()
                } label: {
                    HStack {
                        Label("The cookbook · all sessions (\(sessions.count))", systemImage: "book.closed.fill")
                            .font(.kukit(.headline, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .card()
                }
                .buttonStyle(.plain)
                .hoverHighlight(radius: Theme.cardRadius)
            }
            .padding(20)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .kukitScreen()
        .navigationTitle("Stats")
    }

    // MARK: Achievements

    private var achievementsCard: some View {
        let list = achievements
        let unlocked = list.filter(\.isUnlocked).count
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle("Achievements", systemImage: "star.fill")
                Text("\(unlocked) of \(list.count)")
                    .font(.kukit(.footnote, weight: .bold)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(list) { achievement in AchievementTile(achievement: achievement) }
            }
        }
        .card(padding: 18)
    }

    // MARK: Charts

    @ViewBuilder
    private var dailyChart: some View {
        Chart {
            ForEach(daily) { item in
                BarMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Minutes", item.seconds / 60)
                )
                .foregroundStyle(goalSeconds > 0 && item.seconds >= goalSeconds ? Theme.basil : Theme.accent)
                .cornerRadius(5)
            }
            if goalMinutes > 0 {
                RuleMark(y: .value("Goal", goalMinutes))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .foregroundStyle(Theme.butter)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal").font(.kukit(.caption2, weight: .bold)).foregroundStyle(.secondary)
                    }
            }
        }
        .chartXAxis {
            if range == .week {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
        }
        .chartYScale(domain: 0...yAxisMax)
        .chartYAxis {
            AxisMarks(values: .stride(by: yAxisStep)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(minutes == 0 ? "0" : DurationFormat.short(minutes * 60))
                    }
                }
            }
        }
        .accessibilityLabel("Focus time per day")
        .accessibilityValue("Total \(DurationFormat.short(totalSeconds))")
    }

    /// Whole 30-minute / 1-hour steps instead of whatever the chart would pick (50m, 1h 40m…).
    private var yAxisStep: Double {
        let peak = max(daily.map { $0.seconds / 60 }.max() ?? 0, Double(goalMinutes))
        if peak <= 150 { return 30 }
        if peak <= 400 { return 60 }
        return 120
    }

    private var yAxisMax: Double {
        let peak = max(daily.map { $0.seconds / 60 }.max() ?? 0, Double(goalMinutes))
        return (peak / yAxisStep).rounded(.up) * yAxisStep
    }

    private func courseBar(_ entry: CourseTotal) -> some View {
        let course = courses.first { $0.id == entry.courseID }
        let maxSeconds = byCourse.first?.seconds ?? 1
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                CourseBadge(color: course?.color ?? .secondary, symbol: course?.symbolName ?? "questionmark", size: 26)
                Text(course?.name ?? "Deleted course").font(.kukit(.subheadline, weight: .bold))
                Spacer()
                Text(DurationFormat.short(entry.seconds)).font(.kukit(.subheadline, weight: .semibold)).monospacedDigit()
            }
            RecipeBar(progress: entry.seconds / max(maxSeconds, 1), tint: course?.color ?? .secondary, height: 9)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One small achievement: a medal when earned, a progress bar while it's still cooking.
struct AchievementTile: View {
    var achievement: Achievement

    private var symbol: String {
        switch achievement.id {
        case "first-session": "fork.knife"
        case "goal-today": "star.fill"
        case "personal-best": "trophy.fill"
        case let id where id.hasPrefix("streak"): "flame.fill"
        default: "clock.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(achievement.isUnlocked ? Theme.butter : Theme.softBackground.opacity(0.6))
                Image(systemName: achievement.isUnlocked ? symbol : "lock.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(achievement.isUnlocked ? Color(hex: "3A2E00") : Color.secondary)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(achievement.title).font(.kukit(.subheadline, weight: .heavy))
                Text(achievement.detail).font(.kukit(.caption, weight: .medium)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !achievement.isUnlocked {
                    RecipeBar(progress: achievement.progress, tint: Theme.butter, height: 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            achievement.isUnlocked ? Theme.butter.opacity(0.16) : Theme.softBackgroundFaint,
            in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue(achievement.isUnlocked ? "Unlocked" : "\(Int(achievement.progress * 100)) percent")
    }
}
