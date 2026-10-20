import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    /// `Color(hex: "F15B40")`
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

    init(light: String, dark: String) {
        self.init(light: Color(hex: light), dark: Color(hex: dark))
    }
}

/// Kukit's kitchen palette. Light mode is warm cream; dark mode is warm charcoal with the same
/// accents nudged lighter so they keep their contrast — not an inverted light theme.
enum Theme {
    // Surfaces
    /// Window / screen background (cream).
    static let screenBackground = Color(light: "FFF8ED", dark: "1F1B18")
    /// Elevated cards and input surfaces (warm white).
    static let cardBackground = Color(light: "FFFFFF", dark: "2B2622")
    /// Secondary cards and decorative areas (soft peach).
    static let softBackground = Color(light: "F6D5C6", dark: "4A372E")
    /// A quieter peach for large areas.
    static let softBackgroundFaint = Color(light: "FBE9DE", dark: "352C27")

    // Text
    /// Deep charcoal in light mode, muted cream in dark mode.
    static let ink = Color(light: "252525", dark: "F3E9D8")

    // Accents
    /// Tomato red: primary accent, important buttons, active timer.
    static let accent = Color(light: "F15B40", dark: "FF7458")
    /// Darker tomato for small text on cream (the base tomato is for large or bold elements).
    static let accentText = Color(light: "C23B22", dark: "FF8E76")
    /// Butter yellow: highlights, rewards, progress.
    static let butter = Color(light: "FFD166", dark: "F2C35C")
    /// Basil green: completed work, successful sessions, break time.
    static let basil = Color(light: "588157", dark: "7FB07D")
    static let basilText = Color(light: "3F6A3E", dark: "9CC99A")
    /// Break phases use basil.
    static let breakGreen = basil

    // Lines
    static let border = Color(light: Color(hex: "252525").opacity(0.09), dark: Color(hex: "F3E9D8").opacity(0.10))

    // Shape
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 14
    static let chipRadius: CGFloat = 10
    /// Kept for older call sites.
    static var cornerRadius: CGFloat { cardRadius }
}

enum CoursePalette {
    struct Swatch: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
    }

    /// Course colors: the kitchen accents first, then supporting hues.
    static let colors: [Swatch] = [
        .init(name: "Tomato", hex: "F15B40"),
        .init(name: "Orange", hex: "F08A24"),
        .init(name: "Butter", hex: "E5A91A"),
        .init(name: "Basil", hex: "588157"),
        .init(name: "Teal", hex: "1FA3A3"),
        .init(name: "Blueberry", hex: "3B82F6"),
        .init(name: "Indigo", hex: "5B5BD6"),
        .init(name: "Plum", hex: "9B59D0"),
        .init(name: "Berry", hex: "E5478B"),
        .init(name: "Cocoa", hex: "8B5E3C"),
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

// MARK: - Typography

extension Font {
    /// Kukit's rounded type: bold, friendly headings with Dynamic Type support.
    static func kukit(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

// MARK: - Screen chrome

/// Cream (or warm charcoal) with a faint peach glow in one corner. Static and cheap.
struct KukitBackground: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.screenBackground
            Circle()
                .fill(Theme.softBackground.opacity(0.35))
                .frame(width: 420, height: 420)
                .blur(radius: 70)
                .offset(x: 160, y: -200)
                .allowsHitTesting(false)
        }
        .clipped()
    }
}

extension View {
    /// The standard screen backdrop.
    func kukitScreen() -> some View {
        background(KukitBackground().ignoresSafeArea())
    }

    /// Lists and forms: hide the system grouped background and use the kitchen surfaces.
    func kukitList() -> some View {
        scrollContentBackground(.hidden).background(KukitBackground().ignoresSafeArea())
    }
}

/// A `Section` whose rows sit on warm white cards instead of the system grouped color.
struct KSection<Content: View, Header: View, Footer: View>: View {
    private let content: Content
    private let header: Header
    private let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        Section {
            content
        } header: {
            header
        } footer: {
            footer
        }
        .listRowBackground(Theme.cardBackground)
    }
}

extension KSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension KSection where Header == Text, Footer == EmptyView {
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
    }

    init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
    }
}

extension KSection where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
}

extension KSection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}
