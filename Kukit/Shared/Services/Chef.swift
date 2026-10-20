import Foundation
import Observation
import SwiftUI
import KukitCore

/// Chef Kukit's voice. Lines come from `ChefMessages` (tested in KukitCore); this picks a stable
/// seed and honours the "Chef's humor" switch in Settings.
enum Chef {
    static var humorEnabled: Bool {
        UserDefaults.standard.object(forKey: Prefs.chefHumor) as? Bool ?? true
    }

    static func line(_ context: ChefContext, seed: Int) -> String {
        humorEnabled ? ChefMessages.message(context, seed: seed) : ChefMessages.plain(context)
    }

    /// A seed that changes once a day, so a screen's line is stable while you use it.
    static func daySeed(_ date: Date = .now) -> Int {
        let parts = Calendar.current.dateComponents([.year, .dayOfYear], from: date)
        return (parts.year ?? 0) * 400 + (parts.dayOfYear ?? 0)
    }
}

/// A short, non-blocking message at the top of the window: a finished task, a goal reached, or a
/// problem such as the music file not loading.
@MainActor
@Observable
final class ToastCenter {
    static let shared = ToastCenter()

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var detail: String?
        var mood: ChefMood
        var isError: Bool
    }

    private(set) var current: Toast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func show(_ title: String, detail: String? = nil, mood: ChefMood = .celebrate,
              isError: Bool = false, duration: TimeInterval = 3.2) {
        let toast = Toast(title: title, detail: detail, mood: mood, isError: isError)
        withAnimation(.snappy) { current = toast }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismiss(toast.id)
        }
    }

    func dismiss(_ id: UUID? = nil) {
        guard id == nil || current?.id == id else { return }
        withAnimation(.snappy) { current = nil }
    }
}

struct ToastHost: ViewModifier {
    @State private var toasts = ToastCenter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = toasts.current {
                HStack(spacing: 10) {
                    if toast.isError {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.accent)
                    } else {
                        ChefKukit(mood: toast.mood, size: 40, animated: false)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(toast.title).font(.kukit(.subheadline, weight: .heavy))
                        if let detail = toast.detail {
                            Text(detail).font(.kukit(.caption, weight: .medium)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button { toasts.dismiss(toast.id) } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: 420)
                .background(Theme.cardBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.top, 8)
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}
