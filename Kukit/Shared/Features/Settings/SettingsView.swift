import SwiftUI
import SwiftData
import UserNotifications
import KukitCore

#if os(macOS)
import ServiceManagement
#endif

struct SettingsView: View {
    @AppStorage(Prefs.autoStartNext) private var autoStartNext = true
    @AppStorage(Prefs.minimumSessionMinutes) private var minimumMinutes = 1
    @AppStorage(Prefs.dailyGoalMinutes) private var goalMinutes = 120
    @AppStorage(Prefs.keepScreenAwake) private var keepAwake = true
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true
    @AppStorage(Prefs.menuBarCountdown) private var menuBarCountdown = true

    @Environment(\.openURL) private var openURL
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section("Timer") {
                Toggle("Start next phase automatically", isOn: $autoStartNext)
                Stepper(value: $minimumMinutes, in: 0...5) {
                    LabeledContent("Minimum session", value: minimumMinutes == 0 ? "Save everything" : "\(minimumMinutes) min")
                }
                #if os(iOS)
                Toggle("Keep screen awake while timing", isOn: $keepAwake)
                #endif
                NavigationLink {
                    PresetsSettingsView()
                } label: {
                    Label("Custom techniques", systemImage: "slider.horizontal.3")
                }
            }

            Section("Goal") {
                Stepper(value: $goalMinutes, in: 15...600, step: 15) {
                    LabeledContent("Daily focus goal", value: DurationFormat.short(TimeInterval(goalMinutes * 60)))
                }
            }

            Section {
                LabeledContent("Alerts", value: statusText)
                if notificationStatus == .notDetermined {
                    Button("Allow notifications") {
                        Task {
                            await NotificationService.shared.requestAuthorizationIfNeeded()
                            notificationStatus = await NotificationService.shared.authorizationStatus()
                        }
                    }
                } else if notificationStatus == .denied {
                    Button("Open system settings", action: openSystemSettings)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Kukit uses notifications to tell you when a focus round or break ends, even when the app is closed.")
            }

            #if os(macOS)
            Section("Menu bar & login") {
                Toggle("Show timer in the menu bar", isOn: $showMenuBar)
                Toggle("Show countdown next to the icon", isOn: $menuBarCountdown)
                    .disabled(!showMenuBar)
                LaunchAtLoginToggle()
            }
            #endif

            Section("About") {
                LabeledContent("Kukit", value: version)
                Text("Cook it. Study timer, grades and tasks for university.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task { notificationStatus = await NotificationService.shared.authorizationStatus() }
    }

    private var statusText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "On"
        case .denied: "Off"
        default: "Not set up"
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { openURL(url) }
        #endif
    }
}

struct PresetsSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @Query(sort: [SortDescriptor(\TimerPreset.sortOrder), SortDescriptor(\TimerPreset.createdAt)])
    private var presets: [TimerPreset]
    @State private var editing: TimerPreset?
    @State private var creating = false

    var body: some View {
        List {
            Section {
                ForEach(TimerConfig.builtIns) { config in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.name)
                        Text(config.kind == .stopwatch
                             ? "Counts up until you stop"
                             : "\(config.focusMinutes) min focus · \(config.shortBreakMinutes) min break · \(config.longBreakMinutes) min long break after \(config.roundsBeforeLongBreak) rounds")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Built in")
            }

            Section {
                if presets.isEmpty {
                    Text("No custom techniques yet.").foregroundStyle(.secondary)
                }
                ForEach(presets) { preset in
                    Button { editing = preset } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name).foregroundStyle(.primary)
                            Text("\(preset.focusMinutes) min focus · \(preset.shortBreakMinutes) min break · \(preset.longBreakMinutes) min long break after \(preset.roundsBeforeLongBreak) rounds")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(preset) }
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(preset) }
                    }
                }
            } header: {
                Text("Yours")
            }
        }
        .navigationTitle("Techniques")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New technique", systemImage: "plus") { creating = true }
            }
        }
        .sheet(isPresented: $creating) { PresetEditorView(preset: nil) }
        .sheet(item: $editing) { PresetEditorView(preset: $0) }
    }

    private func delete(_ preset: TimerPreset) {
        if timer.selectedPresetID == preset.id.uuidString { timer.selectPreset(.classic) }
        context.delete(preset)
        try? context.save()
    }
}

#if os(macOS)
private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var errorMessage: String?

    var body: some View {
        Toggle("Open Kukit at login", isOn: Binding(
            get: { enabled },
            set: { newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
                enabled = SMAppService.mainApp.status == .enabled
            }
        ))
        if let errorMessage {
            Text(errorMessage).font(.caption).foregroundStyle(.red)
        }
    }
}
#endif
