import Observation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today, focus, tasks, notes, courses, grades, stats, settings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .today: "Today"
        case .focus: "Focus"
        case .tasks: "Tasks"
        case .notes: "Notes"
        case .courses: "Courses"
        case .grades: "Grades"
        case .stats: "Stats"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .focus: "timer"
        case .tasks: "checklist"
        case .notes: "note.text"
        case .courses: "books.vertical"
        case .grades: "graduationcap"
        case .stats: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    /// Launch with `-startSection stats` (any section name) to open straight onto a screen.
    /// Set to show the welcome flow (first launch, or from Settings).
    var showOnboarding = false

    var section: AppSection = AppSection(rawValue: UserDefaults.standard.string(forKey: "startSection") ?? "") ?? .today
}

#if os(iOS)
import UIKit
#endif

enum ScreenAwake {
    /// Keeps the iPhone screen on while the focus screen is showing a running timer.
    @MainActor
    static func set(_ on: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
    }
}
