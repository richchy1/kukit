import SwiftUI

/// iPhone: a tab bar, with a mini timer above it while a session is running.
struct AppRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(TimerController.self) private var timer
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.section) {
            Tab("Today", systemImage: AppSection.today.systemImage, value: AppSection.today) {
                NavigationStack { TodayView() }.miniPlayer()
            }
            Tab("Focus", systemImage: AppSection.focus.systemImage, value: AppSection.focus) {
                NavigationStack { FocusView() }
            }
            Tab("Courses", systemImage: AppSection.courses.systemImage, value: AppSection.courses) {
                NavigationStack { CoursesView() }.miniPlayer()
            }
            Tab("Stats", systemImage: AppSection.stats.systemImage, value: AppSection.stats) {
                NavigationStack { StatsView() }.miniPlayer()
            }
            Tab("Settings", systemImage: AppSection.settings.systemImage, value: AppSection.settings) {
                NavigationStack { SettingsView() }.miniPlayer()
            }
        }
        .refreshTimerWhenActive(timer, scenePhase: scenePhase)
    }
}
