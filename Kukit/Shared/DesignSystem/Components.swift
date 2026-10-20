import SwiftUI
import KukitCore

// MARK: - Cards

enum CardTone {
    /// Warm white (elevated surface).
    case plain
    /// Soft peach for secondary or decorative cards.
    case soft
    /// Tomato-tinted, for the thing you should look at.
    case accent
    /// Basil-tinted, for completed things.
    case success
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    var tone: CardTone = .plain
    @Environment(\.colorScheme) private var scheme

    private var fill: Color {
        switch tone {
        case .plain: Theme.cardBackground
        case .soft: Theme.softBackgroundFaint
        case .accent: Theme.accent.opacity(scheme == .dark ? 0.16 : 0.10)
        case .success: Theme.basil.opacity(scheme == .dark ? 0.20 : 0.12)
        }
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The shadow belongs to the background layer only. Applied to the whole card it would be
            // re-rendered every time the contents change (every second, for the timer).
            .background {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(fill)
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.045), radius: 8, y: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
    }
}

extension View {
    func card(padding: CGFloat = 16, tone: CardTone = .plain) -> some View {
        modifier(CardModifier(padding: padding, tone: tone))
    }
}

// MARK: - Buttons

struct KukitButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, danger }

    var kind: Kind = .primary
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        KukitButtonBody(configuration: configuration, kind: kind, tint: tint)
    }
}

private struct KukitButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: KukitButtonStyle.Kind
    let tint: Color?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var base: Color { tint ?? Theme.accent }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary: Theme.ink
        case .ghost: tint ?? Theme.accentText
        case .danger: Theme.accentText
        }
    }

    private var background: Color {
        switch kind {
        case .primary: base
        case .secondary: tint.map { $0.opacity(0.17) } ?? Theme.softBackground.opacity(0.7)
        case .ghost: .clear
        case .danger: Theme.accent.opacity(0.12)
        }
    }

    var body: some View {
        configuration.label
            .font(.kukit(.body, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .ghost ? 8 : 18)
            .frame(minHeight: kind == .ghost ? 32 : 44)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(Color.white.opacity(hovering && isEnabled && kind != .ghost ? 0.14 : 0))
            }
            .overlay {
                if hovering && isEnabled && kind == .ghost {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(Theme.accent.opacity(0.08))
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: configuration.isPressed)
            #if os(macOS)
            .onHover { hovering = $0 }
            #endif
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

extension ButtonStyle where Self == KukitButtonStyle {
    static func kukit(_ kind: KukitButtonStyle.Kind = .primary, tint: Color? = nil) -> KukitButtonStyle {
        KukitButtonStyle(kind: kind, tint: tint)
    }
}

/// A subtle lift when the pointer is over a row or card (Mac only; no-op on iPhone).
struct HoverHighlight: ViewModifier {
    var radius: CGFloat = Theme.controlRadius
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            #if os(macOS)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.softBackground.opacity(hovering ? 0.35 : 0))
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            #endif
    }
}

extension View {
    func hoverHighlight(radius: CGFloat = Theme.controlRadius) -> some View {
        modifier(HoverHighlight(radius: radius))
    }
}

// MARK: - Progress

/// A plain progress ring (goal progress, mini-player). The big timer uses `SimmerRing`.
struct ProgressRing<Content: View>: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.17), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.002, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
        .padding(lineWidth / 2)
    }
}

extension ProgressRing where Content == EmptyView {
    init(progress: Double, tint: Color, lineWidth: CGFloat = 14) {
        self.init(progress: progress, tint: tint, lineWidth: lineWidth) { EmptyView() }
    }
}

/// The focus-timer dial: a kitchen-timer ring with tick marks, a butter "ember" at the head of the
/// arc, and (while running) a few wisps of steam. The arc moves a hair every half second, so it is
/// deliberately not animated: animating it would redraw the whole dial every frame for no visible gain.
struct SimmerRing<Content: View>: View {
    var progress: Double
    var tint: Color
    var isRunning: Bool
    var lineWidth: CGFloat = 16
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = (side - lineWidth) / 2
            let clamped = max(0.002, min(1, progress))
            ZStack {
                DialTicks(radius: radius + lineWidth / 2 + 12)
                    .frame(width: side, height: side)
                Circle().stroke(Theme.softBackground.opacity(0.75), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                // The ember at the head of the arc.
                Circle()
                    .fill(Theme.butter)
                    .frame(width: lineWidth * 0.55, height: lineWidth * 0.55)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(clamped * 360))
                content
                if isRunning && !reduceMotion {
                    SteamWisps(tint: tint)
                        .frame(width: side * 0.3, height: side * 0.12)
                        .offset(y: -(side / 2) - 4)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .padding(.top, 14)
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The 60 tick marks, drawn once. Its only input is the radius, so SwiftUI never redraws it while
/// the timer's digits and arc update.
struct DialTicks: View, Equatable {
    var radius: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for index in 0..<60 {
                let major = index % 5 == 0
                let angle = Double(index) * .pi / 30 - .pi / 2
                let length: CGFloat = major ? 9 : 5
                var path = Path()
                path.move(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                path.addLine(to: CGPoint(x: center.x + cos(angle) * (radius - length), y: center.y + sin(angle) * (radius - length)))
                context.stroke(
                    path, with: .color(Theme.ink.opacity(major ? 0.28 : 0.12)),
                    style: StrokeStyle(lineWidth: major ? 2.5 : 1.5, lineCap: .round)
                )
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

extension SimmerRing where Content == EmptyView {
    init(progress: Double, tint: Color, isRunning: Bool, lineWidth: CGFloat = 16) {
        self.init(progress: progress, tint: tint, isRunning: isRunning, lineWidth: lineWidth) { EmptyView() }
    }
}

/// Three slow curls of steam. Redraws ~12 times a second, and only exists while a timer runs.
struct SteamWisps: View {
    var tint: Color
    /// Steam rises for a few seconds every half minute rather than all the time.
    @State private var puffing = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !puffing)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                guard puffing else { return }
                for index in 0..<3 {
                    let phase = (t * 0.45 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    let x = size.width * (0.2 + 0.3 * Double(index)) + sin(t * 1.3 + Double(index)) * 3
                    let y = size.height * (1 - phase)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y + 8))
                    path.addQuadCurve(to: CGPoint(x: x + 2, y: y - 8), control: CGPoint(x: x + 7, y: y))
                    context.stroke(
                        path, with: .color(tint.opacity(0.5 * sin(phase * .pi))),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                }
            }
        }
        .task {
            while !Task.isCancelled {
                puffing = true
                try? await Task.sleep(for: .seconds(6))
                puffing = false
                try? await Task.sleep(for: .seconds(24))
            }
        }
    }
}

/// A linear progress bar: a rounded track with a filled "batter" bar and a butter highlight.
struct RecipeBar: View {
    var progress: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * max(0, min(1, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.16))
                if width > 0 {
                    Capsule().fill(tint)
                        .frame(width: max(height, width))
                        .overlay(alignment: .topLeading) {
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: height * 0.3)
                                .padding(.horizontal, height * 0.4)
                                .padding(.top, height * 0.15)
                        }
                }
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: progress)
        .accessibilityElement()
        .accessibilityValue("\(Int((max(0, min(1, progress)) * 100).rounded())) percent")
    }
}

// MARK: - Small pieces

/// A course's colored badge with its symbol.
struct CourseBadge: View {
    var color: Color
    var symbol: String
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// A small label with an icon: urgency, priority, status. Icon + text, never color alone.
struct Chip: View {
    var text: String
    var systemImage: String?
    var tint: Color
    var filled = false
    /// Override for the label color (butter chips use dark ink).
    var textColor: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.kukit(.caption, weight: .bold))
        .foregroundStyle(textColor ?? (filled ? Color.white : tint))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            filled ? tint : tint.opacity(0.14),
            in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var systemImage: String? = nil
    var tint: Color = Theme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).foregroundStyle(tint).imageScale(.small) }
                Text(title).font(.kukit(.caption, weight: .semibold)).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.kukit(.title2, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// An empty state with Chef Kukit and a kitchen-flavoured line.
struct EmptyStateView: View {
    var mood: ChefMood = .noTasks
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    init(mood: ChefMood = .noTasks, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.mood = mood
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 10) {
            ChefKukit(mood: mood, size: 96, animated: false)
            Text(title).font(.kukit(.title3, weight: .heavy)).multilineTextAlignment(.center)
            Text(message)
                .font(.kukit(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.kukit(.primary))
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }
}

/// The big rounded timer digits used on Focus, the mini player and the menu bar popover.
struct TimerDigits: View {
    var text: String
    var size: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }
}

/// A section heading in Kukit's voice.
struct SectionTitle: View {
    var title: String
    var systemImage: String? = nil
    var trailing: AnyView? = nil

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(Theme.accent)
            }
            Text(title).font(.kukit(.title3, weight: .heavy))
            Spacer(minLength: 0)
        }
        .accessibilityAddTraits(.isHeader)
    }
}
