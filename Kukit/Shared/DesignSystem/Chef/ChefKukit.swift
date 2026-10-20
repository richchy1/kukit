import SwiftUI

/// How Chef Kukit feels right now.
enum ChefMood: String, CaseIterable {
    case idle        // ready to work
    case ready       // getting ready to cook (session starting)
    case working     // focused on the task
    case breakTime   // relaxing with a mug
    case celebrate   // session complete
    case goalDone    // daily goal reached
    case noTasks     // suggesting tomorrow's ingredients

    /// How a mood animates. Nothing runs continuously: a mascot that never stops redrawing would
    /// cost battery for the whole length of a study session.
    enum Rhythm {
        /// Plays for this many seconds when it appears, then rests on its pose.
        case once(seconds: Double)
        /// Plays for `active` seconds out of every `period` seconds (a little stir now and then).
        case pulse(active: Double, period: Double)
    }

    var rhythm: Rhythm {
        switch self {
        case .working: .pulse(active: 2.5, period: 40)
        case .breakTime: .pulse(active: 3, period: 30)
        case .idle, .noTasks, .ready, .celebrate, .goalDone: .once(seconds: 3)
        }
    }

    var frameInterval: Double { 1.0 / 15 }

    var spokenName: String {
        switch self {
        case .idle: "ready to work"
        case .ready: "getting ready to cook"
        case .working: "focused"
        case .breakTime: "on a break"
        case .celebrate: "celebrating"
        case .goalDone: "celebrating today's goal"
        case .noTasks: "thinking about tomorrow's ingredients"
        }
    }
}

/// Chef Kukit: a small cartoon chef with a white hat, a tomato-red apron, round eyes and a tiny
/// spatula, drawn entirely with SwiftUI paths so it scales from an icon-sized badge to a hero
/// illustration. Animation is optional, respects Reduce Motion, and comes to rest on its own for
/// celebrations.
struct ChefKukit: View {
    var mood: ChefMood = .idle
    var size: CGFloat = 80
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing = false

    var body: some View {
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation(minimumInterval: mood.frameInterval, paused: !playing)) { timeline in
                    art(t: playing ? timeline.date.timeIntervalSinceReferenceDate : 0)
                }
            } else {
                art(t: 0)
            }
        }
        .frame(width: size, height: size)
        .task(id: mood) {
            guard animated else { return }
            switch mood.rhythm {
            case .once(let seconds):
                playing = true
                try? await Task.sleep(for: .seconds(seconds))
                playing = false
            case .pulse(let active, let period):
                while !Task.isCancelled {
                    playing = true
                    try? await Task.sleep(for: .seconds(active))
                    playing = false
                    try? await Task.sleep(for: .seconds(max(1, period - active)))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Chef Kukit, \(mood.spokenName)")
    }

    private func art(t: Double) -> some View {
        Canvas { context, canvasSize in
            ChefArt.draw(&context, size: canvasSize, mood: mood, t: t)
        }
    }
}

/// The drawing, in a 100 × 100 design space.
enum ChefArt {
    private static let outline = Color(hex: "2B2321")
    private static let skin = Color(hex: "FFE2CE")
    private static let hat = Color.white
    private static let wood = Color(hex: "D9A566")

    static func draw(_ context: inout GraphicsContext, size: CGSize, mood: ChefMood, t: Double) {
        let scale = min(size.width, size.height) / 100
        context.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
        context.scaleBy(x: scale, y: scale)

        // Soft ground shadow (stays put while the chef moves).
        context.fill(Path(ellipseIn: CGRect(x: 28, y: 92, width: 44, height: 6)), with: .color(.black.opacity(0.10)))

        var bob = 0.0
        switch mood {
        case .idle, .noTasks: bob = sin(t * 1.9) * 1.0
        case .breakTime: bob = sin(t * 1.2) * 0.8
        case .ready: bob = -abs(sin(t * 3.5)) * 2.5
        case .working: bob = sin(t * 5) * 0.4
        case .celebrate, .goalDone: bob = -abs(sin(t * 6)) * 6
        }
        context.translateBy(x: 0, y: bob)

        let line = StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)

        // Hands (positions depend on mood).
        let leftHand: CGPoint
        let rightHand: CGPoint
        switch mood {
        case .celebrate, .goalDone:
            let wave = sin(t * 9) * 3
            leftHand = CGPoint(x: 19, y: 50 + wave)
            rightHand = CGPoint(x: 81, y: 50 - wave)
        case .breakTime:
            leftHand = CGPoint(x: 28, y: 78)
            rightHand = CGPoint(x: 77, y: 82)
        default:
            leftHand = CGPoint(x: 21, y: 80)
            rightHand = CGPoint(x: 79, y: 76)
        }

        // Arms
        func arm(from start: CGPoint, to end: CGPoint) {
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(outline), style: StrokeStyle(lineWidth: 8.4, lineCap: .round))
            context.stroke(path, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        arm(from: CGPoint(x: 30, y: 70), to: leftHand)
        arm(from: CGPoint(x: 70, y: 70), to: rightHand)

        // Body / apron
        let body = Path(roundedRect: CGRect(x: 26, y: 62, width: 48, height: 32), cornerRadius: 15)
        context.stroke(body, with: .color(outline), style: line)
        context.fill(body, with: .color(Theme.accent))
        let pocket = Path(roundedRect: CGRect(x: 40, y: 78, width: 20, height: 10), cornerRadius: 4)
        context.fill(pocket, with: .color(.white.opacity(0.92)))
        context.stroke(pocket, with: .color(outline.opacity(0.45)), style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
        // Neck tie
        var tie = Path()
        tie.move(to: CGPoint(x: 42, y: 62)); tie.addLine(to: CGPoint(x: 50, y: 70)); tie.addLine(to: CGPoint(x: 58, y: 62))
        context.stroke(tie, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

        // Hands
        for hand in [leftHand, rightHand] {
            let rect = CGRect(x: hand.x - 5, y: hand.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: rect), with: .color(skin))
            context.stroke(Path(ellipseIn: rect), with: .color(outline), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }

        // Spatula in the right hand
        drawSpatula(&context, hand: rightHand, mood: mood, t: t)
        if mood == .breakTime { drawMug(&context, hand: leftHand, t: t) }

        // Head
        let head = Path(ellipseIn: CGRect(x: 25, y: 22, width: 50, height: 50))
        context.stroke(head, with: .color(outline), style: line)
        context.fill(head, with: .color(skin))
        for x in [35.0, 65.0] {
            context.fill(Path(ellipseIn: CGRect(x: x - 4.5, y: 52, width: 9, height: 6)), with: .color(Theme.accent.opacity(0.30)))
        }

        drawFace(&context, mood: mood, t: t)
        drawHat(&context)

        // Mood extras
        switch mood {
        case .celebrate, .goalDone: drawConfetti(&context, t: t, goal: mood == .goalDone)
        case .noTasks: drawThought(&context, t: t)
        case .ready: drawSparkles(&context, t: t)
        default: break
        }
    }

    // MARK: Parts

    private static func drawHat(_ context: inout GraphicsContext) {
        let puffs = [
            CGRect(x: 25, y: 7, width: 22, height: 22),
            CGRect(x: 39, y: 0, width: 24, height: 24),
            CGRect(x: 53, y: 7, width: 22, height: 22),
        ]
        let band = CGRect(x: 31, y: 20, width: 38, height: 14)
        for rect in puffs { context.stroke(Path(ellipseIn: rect), with: .color(outline), style: StrokeStyle(lineWidth: 4.6)) }
        context.stroke(Path(roundedRect: band, cornerRadius: 4), with: .color(outline), style: StrokeStyle(lineWidth: 4.6, lineJoin: .round))
        for rect in puffs { context.fill(Path(ellipseIn: rect), with: .color(hat)) }
        context.fill(Path(roundedRect: band, cornerRadius: 4), with: .color(hat))
        // Hat band shading + a tomato stripe
        context.fill(Path(roundedRect: CGRect(x: 31, y: 28, width: 38, height: 6), cornerRadius: 3), with: .color(Color(hex: "F1E4D4")))
        context.fill(Path(roundedRect: CGRect(x: 31, y: 25, width: 38, height: 2.6), cornerRadius: 1.3), with: .color(Theme.accent))
    }

    private static func drawFace(_ context: inout GraphicsContext, mood: ChefMood, t: Double) {
        let eyeY = 47.0
        let eyes = [41.0, 59.0]
        let blink = mood == .idle && (t * 0.5).truncatingRemainder(dividingBy: 1) > 0.94
        func dot(_ x: Double, dy: Double = 0, r: Double = 2.8) {
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: eyeY + dy - r, width: r * 2, height: r * 2)), with: .color(outline))
        }
        func arc(_ x: Double, up: Bool) {
            var path = Path()
            path.addArc(center: CGPoint(x: x, y: eyeY + (up ? 2.6 : -2.2)), radius: 3.6,
                        startAngle: .degrees(up ? 200 : 20), endAngle: .degrees(up ? 340 : 160), clockwise: false)
            context.stroke(path, with: .color(outline), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
        func brow(_ x: Double, slant: Double) {
            var path = Path()
            path.move(to: CGPoint(x: x - 4.5, y: 40.5 - slant)); path.addLine(to: CGPoint(x: x + 4.5, y: 40.5 + slant))
            context.stroke(path, with: .color(outline), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }

        switch mood {
        case .celebrate, .goalDone:
            eyes.forEach { arc($0, up: true) }
        case .breakTime:
            eyes.forEach { arc($0, up: false) }
        case .working:
            eyes.forEach { dot($0, r: 2.4) }
            brow(eyes[0], slant: 1.6); brow(eyes[1], slant: -1.6)
        case .ready:
            eyes.forEach { dot($0, r: 3.3) }
            for x in eyes { context.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: eyeY - 2.6, width: 1.8, height: 1.8)), with: .color(.white)) }
        case .noTasks:
            eyes.forEach { dot($0, dy: -1.6) }
        case .idle:
            if blink {
                for x in eyes {
                    var path = Path()
                    path.move(to: CGPoint(x: x - 3, y: eyeY)); path.addLine(to: CGPoint(x: x + 3, y: eyeY))
                    context.stroke(path, with: .color(outline), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                }
            } else {
                eyes.forEach { dot($0) }
            }
        }

        // Mouth
        var mouth = Path()
        switch mood {
        case .celebrate, .goalDone:
            mouth.addArc(center: CGPoint(x: 50, y: 55), radius: 6, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            mouth.closeSubpath()
            context.fill(mouth, with: .color(outline))
            context.fill(Path(ellipseIn: CGRect(x: 46.5, y: 58.5, width: 7, height: 4)), with: .color(Theme.accent))
        case .working:
            mouth.move(to: CGPoint(x: 46, y: 57)); mouth.addLine(to: CGPoint(x: 54, y: 57))
            context.stroke(mouth, with: .color(outline), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        case .ready:
            mouth.addArc(center: CGPoint(x: 50, y: 53), radius: 6.5, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
            context.stroke(mouth, with: .color(outline), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
        default:
            mouth.addArc(center: CGPoint(x: 50, y: 54), radius: 5, startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
            context.stroke(mouth, with: .color(outline), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
    }

    private static func drawSpatula(_ context: inout GraphicsContext, hand: CGPoint, mood: ChefMood, t: Double) {
        var angle: Double
        switch mood {
        case .working: angle = 26 + sin(t * 4.2) * 16           // stirring
        case .ready: angle = 36 + sin(t * 8) * 6
        case .celebrate, .goalDone: angle = 32 + sin(t * 10) * 10
        case .breakTime: angle = -8
        default: angle = 24 + sin(t * 1.9) * 2
        }
        var local = context
        local.translateBy(x: hand.x, y: hand.y)
        local.rotate(by: .degrees(angle))
        let handle = Path(roundedRect: CGRect(x: -1.8, y: -19, width: 3.6, height: 17), cornerRadius: 1.8)
        let blade = Path(roundedRect: CGRect(x: -4.6, y: -31, width: 9.2, height: 14), cornerRadius: 3.2)
        for shape in [handle, blade] { local.stroke(shape, with: .color(outline), style: StrokeStyle(lineWidth: 3.4, lineJoin: .round)) }
        local.fill(handle, with: .color(wood))
        local.fill(blade, with: .color(Color(hex: "E8BA7C")))
        // slots in the blade
        for x in [-2.0, 2.0] {
            var slot = Path()
            slot.move(to: CGPoint(x: x, y: -28)); slot.addLine(to: CGPoint(x: x, y: -20))
            local.stroke(slot, with: .color(outline.opacity(0.55)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
        // The hand grips over the handle.
        let grip = CGRect(x: -5, y: -5, width: 10, height: 10)
        local.fill(Path(ellipseIn: grip), with: .color(skin))
        local.stroke(Path(ellipseIn: grip), with: .color(outline), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private static func drawMug(_ context: inout GraphicsContext, hand: CGPoint, t: Double) {
        let mug = CGRect(x: hand.x - 8, y: hand.y - 15, width: 14, height: 13)
        context.stroke(Path(roundedRect: mug, cornerRadius: 3), with: .color(outline), style: StrokeStyle(lineWidth: 2.6))
        context.fill(Path(roundedRect: mug, cornerRadius: 3), with: .color(.white))
        var handle = Path()
        handle.addArc(center: CGPoint(x: mug.maxX + 1, y: mug.midY), radius: 4, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        context.stroke(handle, with: .color(outline), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        for index in 0..<2 {
            let phase = (t * 0.6 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
            var steam = Path()
            let x = mug.minX + 4 + Double(index) * 6
            steam.move(to: CGPoint(x: x, y: mug.minY - 1))
            steam.addQuadCurve(to: CGPoint(x: x + 1, y: mug.minY - 9), control: CGPoint(x: x + 4, y: mug.minY - 5))
            context.stroke(steam, with: .color(outline.opacity(0.35 * (1 - phase) + 0.1)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
    }

    private static func drawConfetti(_ context: inout GraphicsContext, t: Double, goal: Bool) {
        let colors = [Theme.butter, Theme.accent, Theme.basil, Color(hex: "FFB3A0")]
        for index in 0..<14 {
            let seed = Double(index) * 37.7
            let x = 8 + (seed.truncatingRemainder(dividingBy: 84))
            let fall = (t * (14 + Double(index % 4) * 3) + Double(index) * 9).truncatingRemainder(dividingBy: 70)
            let y = -4 + fall
            var piece = context
            piece.translateBy(x: x + sin(t * 3 + seed) * 2, y: y)
            piece.rotate(by: .degrees(t * 160 + seed))
            piece.fill(Path(CGRect(x: -2, y: -1, width: 4, height: 2)), with: .color(colors[index % colors.count]))
        }
        if goal {
            drawStar(&context, center: CGPoint(x: 88, y: 12), radius: 7, tilt: sin(t * 2) * 8)
            drawStar(&context, center: CGPoint(x: 11, y: 20), radius: 5, tilt: -sin(t * 2) * 8)
        }
    }

    private static func drawStar(_ context: inout GraphicsContext, center: CGPoint, radius: Double, tilt: Double) {
        var path = Path()
        for point in 0..<10 {
            let r = point % 2 == 0 ? radius : radius * 0.45
            let angle = Double(point) * .pi / 5 - .pi / 2 + tilt * .pi / 180
            let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            point == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        context.fill(path, with: .color(Theme.butter))
        context.stroke(path, with: .color(outline), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
    }

    private static func drawSparkles(_ context: inout GraphicsContext, t: Double) {
        for (index, spot) in [CGPoint(x: 14, y: 22), CGPoint(x: 88, y: 18), CGPoint(x: 84, y: 40)].enumerated() {
            let pulse = 0.6 + 0.4 * sin(t * 6 + Double(index) * 2)
            var path = Path()
            path.move(to: CGPoint(x: spot.x, y: spot.y - 5 * pulse)); path.addLine(to: CGPoint(x: spot.x, y: spot.y + 5 * pulse))
            path.move(to: CGPoint(x: spot.x - 5 * pulse, y: spot.y)); path.addLine(to: CGPoint(x: spot.x + 5 * pulse, y: spot.y))
            context.stroke(path, with: .color(Theme.butter), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
    }

    private static func drawThought(_ context: inout GraphicsContext, t: Double) {
        let float = sin(t * 1.6) * 1.2
        for (index, rect) in [CGRect(x: 66, y: 34, width: 4, height: 4), CGRect(x: 72, y: 28, width: 6, height: 6)].enumerated() {
            _ = index
            context.fill(Path(ellipseIn: rect), with: .color(.white))
            context.stroke(Path(ellipseIn: rect), with: .color(outline.opacity(0.6)), style: StrokeStyle(lineWidth: 1.3))
        }
        var bubble = context
        bubble.translateBy(x: 0, y: float)
        let cloud = CGRect(x: 70, y: 4, width: 28, height: 22)
        bubble.fill(Path(ellipseIn: cloud), with: .color(.white))
        bubble.stroke(Path(ellipseIn: cloud), with: .color(outline.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5))
        // a tomato to prep
        bubble.fill(Path(ellipseIn: CGRect(x: 78, y: 11, width: 12, height: 11)), with: .color(Theme.accent))
        bubble.fill(Path(ellipseIn: CGRect(x: 81, y: 8.5, width: 6, height: 3.5)), with: .color(Theme.basil))
    }
}
