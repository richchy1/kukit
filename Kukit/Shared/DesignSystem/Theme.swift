import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    /// `Color(hex: "E8503A")`
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    /// A color that switches with light/dark appearance.
    init(light: Color, dark: Color) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #else
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #endif
    }
}

enum Theme {
    /// Kukit's tomato accent (also set as the asset-catalog AccentColor).
    static let accent = Color(light: Color(hex: "E8503A"), dark: Color(hex: "FF6B52"))
    /// Used for break phases.
    static let breakGreen = Color(light: Color(hex: "2E9E6B"), dark: Color(hex: "4CC38A"))

    static var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    static var screenBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static let cornerRadius: CGFloat = 14
}

enum CoursePalette {
    struct Swatch: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
    }

    static let colors: [Swatch] = [
        .init(name: "Tomato", hex: "E8503A"),
        .init(name: "Orange", hex: "F08A24"),
        .init(name: "Amber", hex: "F2B01E"),
        .init(name: "Lime", hex: "7CB342"),
        .init(name: "Green", hex: "2E9E6B"),
        .init(name: "Teal", hex: "1FA3A3"),
        .init(name: "Blue", hex: "3B82F6"),
        .init(name: "Indigo", hex: "5B5BD6"),
        .init(name: "Purple", hex: "9B59D0"),
        .init(name: "Pink", hex: "E5478B"),
    ]

    static let symbols: [String] = [
        "book.closed", "function", "atom", "flask", "laptopcomputer", "globe",
        "paintpalette", "music.note", "chart.bar", "building.columns", "stethoscope",
        "hammer", "leaf", "character.book.closed", "brain", "pencil.and.ruler",
    ]
}

extension Course {
    var color: Color { Color(hex: colorHex) }
    var displayCode: String { code.isEmpty ? name : code }
}
