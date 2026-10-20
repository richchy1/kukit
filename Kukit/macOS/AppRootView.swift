import SwiftUI

/// Mac: a sidebar with the main sections; the running timer is pinned under the list.
struct AppRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(TimerController.self) private var timer

    private let sections: [AppSection] = [.today, .focus, .tasks, .notes, .courses, .grades, .stats]

    var body: some View {
        let selection = Binding<AppSection?>(
            get: { router.section },
            set: { if let section = $0 { router.section = section } }
        )
        NavigationSplitView {
            List(sections, selection: selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .font(.kukit(.body, weight: .semibold))
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 8) {
                    ChefKukit(mood: .idle, size: 38, animated: false)
                    Text("Kukit").font(.kukit(.title2, weight: .heavy))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
        } detail: {
            NavigationStack {
                switch router.section {
                case .today: TodayView()
                case .focus: FocusView()
                case .tasks: AssignmentsView()
                case .notes: NotesView()
                case .courses: CoursesView()
                case .grades: GradesOverviewView()
                case .stats: StatsView()
                case .settings: SettingsView()
                }
            }
            .id(router.section)
        }
        .frame(minWidth: 860, minHeight: 560)
        .kukitRoot()
    }
}
