import SwiftUI
import SwiftData

@main
struct KukitApp: App {
    private let container: ModelContainer
    @State private var timer: TimerController
    @State private var music: FocusMusicController
    @State private var router = AppRouter()

    #if os(macOS)
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true
    #endif

    init() {
        Prefs.registerDefaults()
        #if DEBUG
        // Debug-only launch flags for verification: `-debugInMemory 1` uses a throwaway store, and
        // `-debugAutostartTimer 1` starts a focus session (without notifications) on launch.
        let debugInMemory = UserDefaults.standard.bool(forKey: "debugInMemory")
        #else
        let debugInMemory = false
        #endif
        do {
            container = try KukitSchema.makeContainer(inMemory: debugInMemory)
        } catch {
            fatalError("Kukit could not open its database: \(error)")
        }
        GradingScales.seedIfNeeded(container.mainContext)
        let music = FocusMusicController()
        music.onError = { message in
            ToastCenter.shared.show("Music unavailable", detail: message, mood: .idle, isError: true, duration: 5)
        }
        _music = State(initialValue: music)
        #if DEBUG
        let debugAutostart = UserDefaults.standard.bool(forKey: "debugAutostartTimer")
        let controller = TimerController(modelContext: container.mainContext, music: music, schedulesNotifications: !debugAutostart)
        if debugAutostart {
            let course = Course(name: "Debug course")
            container.mainContext.insert(course)
            controller.selectCourse(course.id)
            controller.start(config: .classic)
        }
        _timer = State(initialValue: controller)
        #else
        _timer = State(initialValue: TimerController(modelContext: container.mainContext, music: music))
        #endif
    }

    #if os(macOS)
    /// Binding that only writes when the value really changes. Passing the @AppStorage binding
    /// straight to MenuBarExtra makes SwiftUI rewrite it on every update, which spins the CPU in a loop.
    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { showMenuBar },
            set: { newValue in if newValue != showMenuBar { showMenuBar = newValue } }
        )
    }
    #endif

    var body: some Scene {
        WindowGroup("Kukit", id: "main") {
            AppRootView()
                .environment(timer)
                .environment(music)
                .environment(router)
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif

        #if os(macOS)
        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarTimerView()
                .environment(timer)
                .environment(music)
                .environment(router)
                .modelContainer(container)
        } label: {
            MenuBarLabel()
                .environment(timer)
        }
        .menuBarExtraStyle(.window)

        Settings {
            NavigationStack { SettingsView() }
                .environment(timer)
                .environment(music)
                .environment(router)
                .modelContainer(container)
                .frame(width: 520, height: 560)
        }
        #endif
    }
}
