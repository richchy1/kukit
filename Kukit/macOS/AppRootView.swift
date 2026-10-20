import SwiftUI

/// Mac: a sidebar with the main sections; the running timer is pinned under the list.
struct AppRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(TimerController.self) private var timer
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context

    private let sections: [AppSection] = [.today, .focus, .tasks, .courses, .grades, .stats]

    var body: some View {
        let selection = Binding<AppSection?>(
            get: { router.section },
            set: { if let section = $0 { router.section = section } }
        )
        NavigationSplitView {
            List(sections, selection: selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
        } detail: {
            NavigationStack {
                switch router.section {
                case .today: TodayView()
                case .focus: FocusView()
                case .tasks: AssignmentsView()
                case .courses: CoursesView()
                case .grades: GradesOverviewView()
                case .stats: StatsView()
                case .settings, .more: SettingsView()
                }
            }
            .id(router.section)
        }
        .frame(minWidth: 860, minHeight: 560)
        .refreshTimerWhenActive(timer, scenePhase: scenePhase, context: context)
    }
}
