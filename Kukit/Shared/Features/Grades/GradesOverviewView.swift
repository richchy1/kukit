import SwiftUI
import SwiftData
import KukitCore

/// Grade and GPA across all courses, grouped by semester.
struct GradesOverviewView: View {
    @Query(sort: \Course.name) private var allCourses: [Course]
    @Query(sort: \Semester.startDate, order: .reverse) private var semesters: [Semester]
    @Query(sort: \GradingScale.createdAt) private var scales: [GradingScale]

    private var courses: [Course] { allCourses.filter { !$0.isArchived } }
    private var defaultScale: GradeScale { GradingScales.resolve(for: nil, in: scales) }

    private struct Group: Identifiable {
        var id: String
        var title: String
        var courses: [Course]
    }

    private var groups: [Group] {
        var result = semesters.compactMap { semester -> Group? in
            let inSemester = courses.filter { $0.semester?.id == semester.id }
            return inSemester.isEmpty ? nil : Group(id: semester.id.uuidString, title: semester.name, courses: inSemester)
        }
        let loose = courses.filter { $0.semester == nil }
        if !loose.isEmpty { result.append(Group(id: "none", title: result.isEmpty ? "Courses" : "No semester", courses: loose)) }
        return result
    }

    private func gpaInputs(_ list: [Course], projected: Bool) -> [CourseGPAInput] {
        list.map { course in
            let summary = course.gradeSummary
            let percent = projected ? (summary.projectedPercent ?? summary.currentPercent) : summary.currentPercent
            return CourseGPAInput(
                credits: course.credits, percent: percent, countsTowardGPA: course.countsTowardGPA,
                scale: GradingScales.resolve(for: course, in: scales)
            )
        }
    }

    private func gpaText(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "–"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    gpaTile(title: "GPA so far", value: GPACalculator.gpa(gpaInputs(courses, projected: false)))
                    gpaTile(title: "Projected GPA", value: GPACalculator.gpa(gpaInputs(courses, projected: true)))
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("Credit-weighted. Pass/Non-pass courses and courses without scores are left out. Projected uses your planned scores.")
            }

            if courses.isEmpty {
                EmptyStateView(systemImage: "graduationcap", title: "No courses yet",
                               message: "Add courses, then set up their grading to see your GPA here.")
                    .listRowBackground(Color.clear)
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.courses) { course in
                        NavigationLink(value: course) { row(course) }
                    }
                } header: {
                    HStack {
                        Text(group.title)
                        Spacer()
                        Text("GPA \(gpaText(GPACalculator.gpa(gpaInputs(group.courses, projected: false))))")
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Grades")
        .navigationDestination(for: Course.self) { CourseGradesView(course: $0) }
    }

    private func gpaTile(title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(gpaText(value)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                Text("/ \(GradeFormat.number(defaultScale.gpaMax))").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func row(_ course: Course) -> some View {
        let summary = course.gradeSummary
        let scale = GradingScales.resolve(for: course, in: scales)
        let band = summary.currentPercent.flatMap { scale.band(for: $0) }
        return HStack(spacing: 12) {
            CourseBadge(color: course.color, symbol: course.symbolName, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name).font(.body.weight(.medium))
                Text("\(GradeFormat.number(course.credits)) credits\(course.countsTowardGPA ? "" : " · Pass/Non-pass")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if course.hasGrades {
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(GradeFormat.percent(summary.currentPercent)).monospacedDigit()
                        if let band { Text(band.label).fontWeight(.bold).foregroundStyle(course.color) }
                    }
                    if let projected = summary.projectedPercent, summary.currentPercent != nil,
                       abs(projected - (summary.currentPercent ?? 0)) > 0.05 {
                        Text("→ \(GradeFormat.percent(projected))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            } else {
                Text("Set up").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
