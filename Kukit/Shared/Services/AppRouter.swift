import Observation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today, focus, tasks, courses, stats, settings, more

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .today: "Today"
        case .focus: "Focus"
        case .tasks: "Tasks"
        case .courses: "Courses"
        case .stats: "Stats"
        case .settings: "Settings"
        case .more: "More"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .focus: "timer"
        case .tasks: "checklist"
        case .courses: "books.vertical"
        case .stats: "chart.bar.xaxis"
        case .settings: "gearshape"
        case .more: "ellipsis.circle"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var section: AppSection = .today
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
