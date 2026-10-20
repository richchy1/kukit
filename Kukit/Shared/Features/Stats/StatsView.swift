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
    private var daily: [DayTotal] { calculator.dailyTotals(summaries, endingOn: .now, days: range.days) }
    private var totalSeconds: TimeInterval { daily.reduce(0) { $0 + $1.seconds } }
    private var bestDay: DayTotal? { daily.max { $0.seconds < $1.seconds } }
    private var rangeStart: Date { daily.first?.day ?? .now }
    private var sessionCount: Int { sessions.filter { $0.startedAt >= rangeStart }.count }

    private var byCourse: [CourseTotal] {
        calculator.courseTotals(summaries, from: rangeStart, to: .distantFuture)
    }

    private var streak: Int {
        calculator.currentStreak(summaries, goalSeconds: TimeInterval(goalMinutes * 60), asOf: .now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Range", selection: $range) {
                    ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    StatTile(title: "Total focus", value: DurationFormat.short(totalSeconds))
                    StatTile(title: "Daily average", value: DurationFormat.short(totalSeconds / Double(range.days)))
                    StatTile(title: "Best day", value: bestDay.map { DurationFormat.short($0.seconds) } ?? "–")
                    StatTile(title: "Streak", value: streak == 1 ? "1 day" : "\(streak) days")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Focus per day").font(.headline)
                    dailyChart.frame(height: 190)
                }
                .card()

                VStack(alignment: .leading, spacing: 14) {
                    Text("By course").font(.headline)
                    if byCourse.isEmpty {
                        Text("Nothing logged in this period.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(byCourse) { entry in
                        courseBar(entry)
                    }
                }
                .card()

                NavigationLink {
                    HistoryView()
                } label: {
                    HStack {
                        Label("All sessions (\(sessions.count))", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .card()
                }
                .buttonStyle(.plain)
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.screenBackground)
        .navigationTitle("Stats")
    }

    @ViewBuilder
    private var dailyChart: some View {
        Chart {
            ForEach(daily) { item in
                BarMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Minutes", item.seconds / 60)
                )
                .foregroundStyle(Theme.accent.gradient)
                .cornerRadius(4)
            }
            if goalMinutes > 0 {
                RuleMark(y: .value("Goal", goalMinutes))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal").font(.caption2).foregroundStyle(.secondary)
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
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(DurationFormat.short(minutes * 60))
                    }
                }
            }
        }
        .accessibilityLabel("Focus time per day")
        .accessibilityValue("Total \(DurationFormat.short(totalSeconds))")
    }

    private func courseBar(_ entry: CourseTotal) -> some View {
        let course = courses.first { $0.id == entry.courseID }
        let maxSeconds = byCourse.first?.seconds ?? 1
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                CourseBadge(color: course?.color ?? .secondary, symbol: course?.symbolName ?? "questionmark", size: 24)
                Text(course?.name ?? "Deleted course").font(.subheadline.weight(.medium))
                Spacer()
                Text(DurationFormat.short(entry.seconds)).font(.subheadline).monospacedDigit()
            }
            ProgressView(value: entry.seconds, total: max(maxSeconds, 1))
                .tint(course?.color ?? .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
