import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Light haptic feedback on iPhone; does nothing on the Mac.
enum Haptics {
    enum Kind { case tap, success, warning, heavy }

    @MainActor
    static func play(_ kind: Kind) {
        #if os(iOS)
        switch kind {
        case .tap: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .heavy: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        #endif
    }
}
