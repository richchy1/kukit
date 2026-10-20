import SwiftUI

/// iPhone: a tab bar, with a mini timer above it while a session is running.
struct AppRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(TimerController.self) private var timer
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.section) {
            Tab("Today", systemImage: AppSection.today.systemImage, value: AppSection.today) {
                NavigationStack { TodayView() }.miniPlayer()
            }
            Tab("Tasks", systemImage: AppSection.tasks.systemImage, value: AppSection.tasks) {
                NavigationStack { AssignmentsView() }.miniPlayer()
            }
            Tab("Focus", systemImage: AppSection.focus.systemImage, value: AppSection.focus) {
                NavigationStack { FocusView() }
            }
            Tab("Courses", systemImage: AppSection.courses.systemImage, value: AppSection.courses) {
                NavigationStack { CoursesView() }.miniPlayer()
            }
            Tab("More", systemImage: AppSection.more.systemImage, value: AppSection.more) {
                NavigationStack { MoreView() }.miniPlayer()
            }
        }
        .refreshTimerWhenActive(timer, scenePhase: scenePhase, context: context)
    }
}

/// Everything that doesn't get its own tab.
struct MoreView: View {
    var body: some View {
        List {
            NavigationLink { GradesOverviewView() } label: {
                Label("Grades & GPA", systemImage: AppSection.grades.systemImage)
            }
            NavigationLink { StatsView() } label: {
                Label("Stats", systemImage: AppSection.stats.systemImage)
            }
            NavigationLink { SettingsView() } label: {
                Label("Settings", systemImage: AppSection.settings.systemImage)
            }
        }
        .navigationTitle("More")
    }
}
