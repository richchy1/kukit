import SwiftUI
import SwiftData
import KukitCore

/// Shows the welcome flow on first launch (when there is no data yet) and when asked from Settings.
struct OnboardingModifier: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage(Prefs.onboardingDone) private var done = false

    func body(content: Content) -> some View {
        @Bindable var router = router
        content
            .task {
                guard !done else { return }
                // Someone who already has courses (an upgrade or a restored backup) doesn't need the tour.
                let hasCourses = ((try? context.fetchCount(FetchDescriptor<Course>())) ?? 0) > 0
                if hasCourses { done = true } else { router.showOnboarding = true }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $router.showOnboarding) { flow }
            #else
            .sheet(isPresented: $router.showOnboarding) { flow }
            #endif
    }

    private var flow: some View {
        OnboardingView { router.showOnboarding = false; done = true }
    }
}

extension View {
    func onboarding() -> some View { modifier(OnboardingModifier()) }
}

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @AppStorage(Prefs.dailyGoalMinutes) private var goalMinutes = 120
    var onFinish: () -> Void

    enum Step: Int, CaseIterable { case welcome, courses, grading, focus, alerts }

    struct CourseDraft: Identifiable {
        let id = UUID()
        var name = ""
        var credits: Double = 3
    }

    @State private var step: Step = .welcome
    @State private var semesterName = OnboardingView.suggestedSemester()
    @State private var drafts = [CourseDraft(), CourseDraft(), CourseDraft()]
    @State private var template: CategoryTemplate?
    @State private var technique: TimerConfig = .classic
    @State private var wantsAlerts = true
    @Query(sort: \GradingScale.createdAt) private var scales: [GradingScale]

    static func suggestedSemester(now: Date = .now) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        switch calendar.component(.month, from: now) {
        case 3...6: return "Spring \(year)"
        case 7, 8: return "Summer \(year)"
        case 9...12: return "Fall \(year)"
        default: return "Winter \(year)"
        }
    }

    private var filledDrafts: [CourseDraft] {
        drafts.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case .welcome: welcome
                    case .courses: courses
                    case .grading: grading
                    case .focus: focus
                    case .alerts: alerts
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            footer
        }
        .background(Theme.screenBackground)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
        .interactiveDismissDisabled()
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Theme.accent : Color.secondary.opacity(0.25))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    private var footer: some View {
        HStack {
            if step == .welcome {
                Button("Skip for now") { onFinish() }.buttonStyle(.borderless)
            } else {
                Button("Back") { move(-1) }.buttonStyle(.borderless)
            }
            Spacer()
            Button(step == .alerts ? "Start cooking" : "Continue") {
                if step == .alerts { finish() } else { move(1) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private func move(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation { step = next }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent.gradient)
            Text("Welcome to Kukit").font(.largeTitle.bold())
            Text("Cook your semester. A focus timer, your courses, assignments, grades and notes in one place — all stored on this device.")
                .font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                bullet("timer", "Time your study sessions per course")
                bullet("checklist", "Track assignments with reminders")
                bullet("graduationcap", "See your grade and what you need on the final")
                bullet("note.text", "Take Markdown notes for every class")
            }
            .padding(.top, 8)
            Text("This takes about a minute. You can change everything later.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        Label { Text(text) } icon: { Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 24) }
    }

    private var courses: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your courses").font(.title.bold())
            Text("Add what you're taking this semester. Leave extra rows empty.")
                .foregroundStyle(.secondary)
            TextField("Semester", text: $semesterName)
                .textFieldStyle(.roundedBorder)
            VStack(spacing: 10) {
                ForEach($drafts) { $draft in
                    HStack(spacing: 10) {
                        Circle().fill(color(for: draft.id)).frame(width: 12, height: 12)
                        TextField("Course name", text: $draft.name).textFieldStyle(.roundedBorder)
                        Stepper(value: $draft.credits, in: 0...12, step: 0.5) {
                            Text("\(draft.credits.formatted(.number.precision(.fractionLength(0...1)))) cr")
                                .monospacedDigit().frame(width: 52, alignment: .trailing)
                        }
                        .fixedSize()
                    }
                }
            }
            Button("Add another course", systemImage: "plus") { drafts.append(CourseDraft()) }
                .buttonStyle(.borderless)
        }
    }

    private func color(for id: UUID) -> Color {
        let index = drafts.firstIndex { $0.id == id } ?? 0
        return Color(hex: CoursePalette.colors[index % CoursePalette.colors.count].hex)
    }

    private var grading: some View {
        let scale = scales.first(where: \.isDefault)?.scale ?? .korean45
        return VStack(alignment: .leading, spacing: 16) {
            Text("Grading").font(.title.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text("Grading scale: \(scale.name)").font(.headline)
                Text(scale.bands.sorted { $0.minPercent > $1.minPercent }
                        .map { "\($0.label) \(GradeFormat.number($0.minPercent))+" }.joined(separator: "  ·  "))
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Different at your university? Change it any time in Settings ▸ Grading scales.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .card()

            VStack(alignment: .leading, spacing: 8) {
                Text("How is your grade made up?").font(.headline)
                Text("Pick a starting point for your \(filledDrafts.count == 1 ? "course" : "courses") — weights can be edited per course.")
                    .font(.footnote).foregroundStyle(.secondary)
                templateRow(nil, "I'll set it up later")
                ForEach(CategoryTemplate.allCases) { option in templateRow(option, option.title) }
            }
        }
    }

    private func templateRow(_ option: CategoryTemplate?, _ title: String) -> some View {
        Button { template = option } label: {
            HStack {
                Image(systemName: template == option ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(template == option ? Theme.accent : Color.secondary)
                Text(title).foregroundStyle(.primary).multilineTextAlignment(.leading)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(template == option ? .isSelected : [])
    }

    private var focus: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Focus").font(.title.bold())
            Text("Pick a technique to start with. You can switch before every session or make your own.")
                .foregroundStyle(.secondary)
            ForEach(TimerConfig.builtIns) { config in
                Button { technique = config } label: {
                    PresetCard(config: config, isSelected: technique.id == config.id)
                }
                .buttonStyle(.plain)
            }
            Stepper(value: $goalMinutes, in: 15...600, step: 15) {
                LabeledContent("Daily focus goal", value: DurationFormat.short(TimeInterval(goalMinutes * 60)))
            }
            .padding(.top, 8)
        }
    }

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stay on track").font(.title.bold())
            Text("Kukit can tell you when a focus round or break ends and remind you before assignments are due — even when the app is closed.")
                .foregroundStyle(.secondary)
            Toggle("Allow notifications", isOn: $wantsAlerts)
                .toggleStyle(.switch)
                .card()
            Text("Your data never leaves this device. Back it up any time from Settings ▸ Data.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Finish

    private func finish() {
        let semester: Semester? = {
            let name = semesterName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !filledDrafts.isEmpty else { return nil }
            let created = Semester(name: name)
            context.insert(created)
            return created
        }()

        var first: Course?
        for (index, draft) in drafts.enumerated() where !draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let course = Course(
                name: draft.name.trimmingCharacters(in: .whitespaces), credits: draft.credits,
                colorHex: CoursePalette.colors[index % CoursePalette.colors.count].hex,
                symbolName: CoursePalette.symbols[index % CoursePalette.symbols.count], semester: semester
            )
            context.insert(course)
            if let template {
                for (order, part) in template.parts.enumerated() {
                    context.insert(GradeCategory(name: part.0, weight: part.1, sortOrder: order, course: course))
                }
            }
            first = first ?? course
        }
        try? context.save()

        if let first { timer.selectCourse(first.id) }
        timer.selectPreset(technique)
        if wantsAlerts { Task { await NotificationService.shared.requestAuthorizationIfNeeded() } }
        onFinish()
    }
}
