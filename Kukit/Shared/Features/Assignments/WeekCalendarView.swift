import SwiftUI
import SwiftData
import KukitCore

/// A one-week view of due dates: seven columns on wide screens, a day-by-day list on narrow ones.
struct WeekCalendarView: View {
    var assignments: [Assignment]
    var onSelect: (Assignment) -> Void

    @State private var weekOffset = 0

    private var calendar: Calendar { .current }

    private var weekStart: Date {
        let today = calendar.startOfDay(for: .now)
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: start) ?? start
    }

    private var days: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private func items(on day: Date) -> [Assignment] {
        assignments
            .filter { item in item.dueDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            ViewThatFits(in: .horizontal) {
                grid.frame(minWidth: 840)
                list
            }
        }
    }

    private var header: some View {
        HStack {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous week")
            Spacer()
            VStack(spacing: 0) {
                Text("\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \((days.last ?? weekStart).formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.headline)
                if weekOffset != 0 {
                    Button("This week") { weekOffset = 0 }.font(.caption)
                }
            }
            Spacer()
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next week")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal)
    }

    private var grid: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 8) {
                    dayHeader(day)
                    ForEach(items(on: day)) { item in chip(item) }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    calendar.isDateInToday(day) ? Theme.accent.opacity(0.08) : Theme.cardBackground,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    private var list: some View {
        List {
            ForEach(days, id: \.self) { day in
                Section {
                    let dayItems = items(on: day)
                    if dayItems.isEmpty {
                        Text("Nothing due").font(.footnote).foregroundStyle(.tertiary)
                    }
                    ForEach(dayItems) { item in
                        AssignmentRow(assignment: item) { onSelect(item) }
                    }
                } header: {
                    dayHeader(day)
                }
            }
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        HStack(spacing: 6) {
            Text(day, format: .dateTime.weekday(.abbreviated))
                .font(.subheadline.weight(.semibold))
            Text(day, format: .dateTime.day())
                .font(.subheadline)
                .foregroundStyle(calendar.isDateInToday(day) ? Theme.accent : .secondary)
                .fontWeight(calendar.isDateInToday(day) ? .bold : .regular)
        }
    }

    private func chip(_ item: Assignment) -> some View {
        Button { onSelect(item) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.medium))
                    .strikethrough(item.isDone)
                    .lineLimit(2)
                if item.hasDueTime, let due = item.dueDate {
                    Text(due, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background((item.course?.color ?? .secondary).opacity(item.isDone ? 0.12 : 0.25),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
