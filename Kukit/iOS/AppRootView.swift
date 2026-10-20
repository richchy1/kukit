import SwiftUI

/// iPhone: a tab bar, with a mini timer above it while a session is running.
/// Grades, stats and settings live in the menu at the top of Today.
struct AppRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(TimerController.self) private var timer

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
            Tab("Notes", systemImage: AppSection.notes.systemImage, value: AppSection.notes) {
                NotesView().miniPlayer()
            }
        }
        .kukitRoot()
    }
}
