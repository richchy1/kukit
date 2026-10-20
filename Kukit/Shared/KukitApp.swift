import SwiftUI
import SwiftData

@main
struct KukitApp: App {
    private let container: ModelContainer
    @State private var timer: TimerController
    @State private var router = AppRouter()

    #if os(macOS)
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true
    #endif

    init() {
        Prefs.registerDefaults()
        do {
            container = try KukitSchema.makeContainer()
        } catch {
            fatalError("Kukit could not open its database: \(error)")
        }
        _timer = State(initialValue: TimerController(modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup("Kukit", id: "main") {
            AppRootView()
                .environment(timer)
                .environment(router)
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif

        #if os(macOS)
        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarTimerView()
                .environment(timer)
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
                .environment(router)
                .modelContainer(container)
                .frame(width: 520, height: 560)
        }
        #endif
    }
}
