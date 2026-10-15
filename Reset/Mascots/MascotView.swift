import SwiftUI

/// One mascot with its health bar. Health is the share of the session window still left.
struct MascotView: View {
    let status: WindowStatus
    let mood: Mood
    let size: CGFloat
    let now: Date
    var onPlacement: (Placement) -> Void = { _ in }
    var onHide: () -> Void = {}

    @State private var appeared = false
    @State private var hoverSince: Date? = nil

    private var color: Color { Theme.color(for: status.id) }

    /// 0...1 of the window left, by usage when known, otherwise by time.
    private var health: Double? {
        if let b = status.blockedUntil, b > now { return 0 }
        switch status.state {
        case .ready: return 1
        case .unavailable: return nil
        case .active(let end):
            if let u = status.usedPercent { return max(0, 1 - u / 100) }
            // Daily quotas with no usage data: time until reset says nothing about what is left.
            if status.id == "gemini" { return nil }
            return min(1, max(0, end.timeIntervalSince(now) / (5 * 3600)))
        }
    }

    private var label: String {
        if let b = status.blockedUntil, b > now { return "zz " + Fmt.short(b.timeIntervalSince(now)) }
        switch status.state {
        case .ready: return "ready"
        case .unavailable: return "--"
        case .active(let end):
            if let u = status.usedPercent { return "\(Int((100 - u).rounded()))%  \(Fmt.short(end.timeIntervalSince(now)))" }
            return Fmt.short(end.timeIntervalSince(now))
        }
    }

    var body: some View {
        VStack(spacing: size * 0.06) {
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let m = MascotMotion(provider: status.id, mood: mood, t: t, hoverSince: hoverSince)
                ZStack(alignment: .bottom) {
                    Ellipse()
                        .fill(color.opacity(mood == .asleep ? 0.18 : 0.35))
                        .frame(width: size * 0.62, height: size * 0.09)
                        .blur(radius: 6)
                        .scaleEffect(1 - m.lift / 40)
                    if let img = MascotArt.image(status.id, mood) {
                        ZStack {
                            Image(nsImage: img)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                            EyeLids(eyes: MascotArt.eyes(status.id, mood), closure: m.blink)
                        }
                        .frame(width: size, height: size)
                        .modifier(JellyWobble(on: m.jelly > 0, t: t, amp: m.jelly * size / 84, size: size))
                        .rotationEffect(.degrees(m.sway), anchor: .bottom)
                        .scaleEffect(x: m.squashX, y: m.squashY, anchor: .bottom)
                        .offset(x: m.shiver, y: -m.lift - size * 0.03)
                        .id(mood)
                        .transition(.asymmetric(insertion: .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity),
                                                removal: .opacity))
                    }
                    MoodParticles(mood: mood, t: t, size: size, color: color)
                }
                .frame(width: size, height: size + size * 0.06)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.6), value: mood)

            HealthBar(health: health, color: color, label: label, width: size * 0.9)
        }
        .padding(.top, 4)
        .scaleEffect(appeared ? 1 : 0.6, anchor: .bottom)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) { appeared = true } }
        .onHover { h in if h { hoverSince = Date() } }
        .help(tooltip)
        .contextMenu {
            Text(status.name)
            Divider()
            ForEach(Placement.allCases) { p in
                Button(p.label) { onPlacement(p) }
            }
            Divider()
            Button("Hide \(status.name)") { onHide() }
        }
    }

    private var tooltip: String {
        var parts = [status.name]
        if let u = status.usedPercent {
            var s = "\(Int(u.rounded()))% of the window used"
            if let asOf = status.usageAsOf { s += " (as of \(Fmt.when(asOf, now: now)))" }
            parts.append(s)
        }
        if let r = status.resetsAt { parts.append("Resets \(Fmt.when(r, now: now))") }
        if status.state == .ready { parts.append("Fresh window ready") }
        return parts.joined(separator: "\n")
    }
}

/// Ten pill segments. The lit part shifts from the provider's color toward red as health runs out.
struct HealthBar: View {
    let health: Double?
    let color: Color
    let label: String
    let width: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 2) {
                ForEach(0..<10, id: \.self) { i in
                    // Unknown usage: every segment faintly lit, so it reads "no data", not "empty".
                    let lit = health.map { Double(i) < ($0 * 10).rounded(.up) } ?? true
                    Capsule()
                        .fill(lit ? (health == nil ? color.opacity(0.3) : segmentColor) : Color.white.opacity(0.12))
                        .frame(height: 5)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.black.opacity(0.72)))
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            .frame(width: width)

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 1.5)
                .background(Capsule().fill(Color.black.opacity(0.6)))
        }
        .animation(.easeInOut(duration: 0.6), value: health)
    }

    private var segmentColor: Color {
        guard let h = health else { return color }
        if h > 0.5 { return color }
        if h > 0.2 { return Color(hex: 0xFFB13D) }
        return Color(hex: 0xFF4A5E)
    }
}


// MARK: Motion

/// Everything that moves, as a pure function of time, so 30 fps redraws stay cheap and deterministic.
struct MascotMotion {
    var lift = 0.0, sway = 0.0, squashX = 1.0, squashY = 1.0, shiver = 0.0, blink = 0.0, jelly = 0.0

    init(provider: String, mood: Mood, t: Double, hoverSince: Date?) {
        // Each mascot gets its own phase so a row of them never moves in lockstep.
        let seed = Double(abs(provider.hashValue % 997)) / 997
        let tt = t + seed * 10
        let energy: Double = mood == .fresh ? 1 : mood == .waking ? 0.9 : mood == .focused ? 0.6 : mood == .tired ? 0.35 : 0.12
        let isJelly = provider == "gemini" || provider == "antigravity"

        // Breathing with squash and stretch, volume kept roughly constant.
        let breathRate = 0.8 + energy * 1.4
        let br = sin(tt * breathRate)
        squashY = 1 + br * (mood == .asleep ? 0.03 : 0.015)
        squashX = 1 / squashY

        // A hop now and then when fresh: crouch, launch, land with a squash.
        if mood == .fresh || mood == .waking {
            let period = mood == .fresh ? 3.2 : 2.4
            let p = (tt / period).truncatingRemainder(dividingBy: 1)
            if p < 0.08 {
                let c = p / 0.08
                squashY *= 1 - 0.1 * sin(c * .pi); squashX *= 1 + 0.08 * sin(c * .pi)
            } else if p < 0.32 {
                let a = (p - 0.08) / 0.24
                lift = sin(a * .pi) * 9 * energy
                squashY *= 1 + 0.06 * sin(a * .pi); squashX *= 1 - 0.04 * sin(a * .pi)
            } else if p < 0.4 {
                let c = (p - 0.32) / 0.08
                squashY *= 1 - 0.08 * sin(c * .pi); squashX *= 1 + 0.07 * sin(c * .pi)
            }
        } else {
            lift = abs(sin(tt * breathRate * 0.5)) * 1.5 * energy
        }

        // Gentle sway; tired ones droop and sway slower.
        sway = sin(tt * (0.6 + energy * 0.6)) * (1 + energy * 2.2)

        // Tired: a small shiver every few seconds.
        if mood == .tired {
            let p = (tt / 4.5).truncatingRemainder(dividingBy: 1)
            if p < 0.1 { shiver = sin(p * 200) * 1.2 * (1 - p / 0.1) }
        }

        // Blink every 3 to 5 s, sometimes twice. Tired blinks are slow.
        let period = 3.4 + seed * 1.8
        let p = tt.truncatingRemainder(dividingBy: period)
        let dur = mood == .tired ? 0.42 : 0.16
        func lid(_ x: Double) -> Double { x < 0 || x > dur ? 0 : sin(x / dur * .pi) }
        blink = max(lid(p), seed > 0.5 ? lid(p - dur - 0.12) : 0)

        // Soft bodies wobble.
        jelly = isJelly ? (0.6 + energy * 1.4) : 0

        // Hover: a springy jiggle that dies away.
        if let h = hoverSince {
            let d = Date().timeIntervalSince(h)
            if d < 0.9 {
                let k = exp(-5 * d) * sin(d * 28)
                squashY *= 1 + 0.1 * k; squashX *= 1 - 0.08 * k
                sway += 6 * k
                if isJelly { jelly += 3 * exp(-4 * d) }
            }
        }
    }
}

/// Lids drawn over the art's own eyes, in the body's colour, closing from the top with a lash line.
struct EyeLids: View {
    let eyes: [MascotArt.Eye]
    let closure: Double

    var body: some View {
        Canvas { ctx, size in
            guard closure > 0.02 else { return }
            for e in eyes {
                let r = CGRect(x: e.rect.minX * size.width, y: e.rect.minY * size.height,
                               width: e.rect.width * size.width, height: e.rect.height * size.height)
                let eyeShape = Path(ellipseIn: r.insetBy(dx: -r.width * 0.08, dy: -r.height * 0.12))
                ctx.drawLayer { l in
                    l.clip(to: eyeShape)
                    // The lid's lower edge travels to 90% of the eye, so the closed lash line stays inside it.
                    let top = r.minY - r.height * 0.15
                    let bottom = r.minY + r.height * 0.9 * closure
                    let lid = Path(CGRect(x: r.minX - r.width * 0.2, y: top, width: r.width * 1.4, height: max(0, bottom - top)))
                    // Light from above: the lid darkens toward its edge, so it reads as skin, not a sticker.
                    l.fill(lid, with: .linearGradient(Gradient(colors: [e.color, e.color.opacity(0.92), Color.black.opacity(0.35).blended(over: e.color)]),
                                                      startPoint: CGPoint(x: r.midX, y: top), endPoint: CGPoint(x: r.midX, y: bottom)))
                    if closure > 0.55 {
                        var lash = Path()
                        let y = bottom
                        lash.move(to: CGPoint(x: r.minX + r.width * 0.08, y: y - r.height * 0.06))
                        lash.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.08, y: y - r.height * 0.06),
                                          control: CGPoint(x: r.midX, y: y + r.height * 0.12))
                        l.stroke(lash, with: .color(.black.opacity(0.75 * closure)), style: StrokeStyle(lineWidth: max(1, r.height * 0.09), lineCap: .round))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Soft-body wobble for the jelly mascots: a shear anchored at the feet, so the top sways and the base stays put.
struct JellyWobble: ViewModifier {
    let on: Bool
    let t: Double
    let amp: Double
    let size: CGFloat
    func body(content: Content) -> some View {
        if on {
            let shear = sin(t * 2.2) * amp * 0.012
            let stretch = 1 + sin(t * 1.7 + 1) * amp * 0.004
            // Move the feet to the origin, shear and stretch, move back: x' = x + shear·(y − size), y' = size + stretch·(y − size).
            content.transformEffect(
                CGAffineTransform(translationX: 0, y: -size)
                    .concatenating(CGAffineTransform(a: 1, b: 0, c: shear, d: stretch, tx: 0, ty: 0))
                    .concatenating(CGAffineTransform(translationX: 0, y: size))
            )
        } else {
            content
        }
    }
}

/// Zs drifting up when asleep, sparkles when a window has just reset.
struct MoodParticles: View {
    let mood: Mood
    let t: Double
    let size: CGFloat
    let color: Color

    var body: some View {
        Canvas { ctx, sz in
            switch mood {
            case .asleep:
                for i in 0..<3 {
                    let p = ((t / 2.6) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    let x = sz.width * 0.68 + sin(p * 6 + Double(i)) * 6 + Double(i) * 4
                    let y = sz.height * (0.45 - p * 0.45)
                    let fs = size * (0.12 + p * 0.1)
                    ctx.opacity = sin(p * .pi)
                    ctx.draw(Text("z").font(.system(size: fs, weight: .heavy, design: .rounded)).foregroundColor(.white), at: CGPoint(x: x, y: y))
                }
            case .waking, .fresh:
                let count = mood == .waking ? 6 : 2
                for i in 0..<count {
                    let p = ((t / 1.8) + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
                    let ang = Double(i) * 2.4
                    let r = size * (0.32 + p * 0.22)
                    let c = CGPoint(x: sz.width / 2 + cos(ang) * r, y: sz.height * 0.5 + sin(ang) * r * 0.8 - p * 8)
                    let s = size * 0.05 * sin(p * .pi)
                    var star = Path()
                    star.move(to: CGPoint(x: c.x, y: c.y - s * 2)); star.addLine(to: CGPoint(x: c.x + s * 0.5, y: c.y - s * 0.5))
                    star.addLine(to: CGPoint(x: c.x + s * 2, y: c.y)); star.addLine(to: CGPoint(x: c.x + s * 0.5, y: c.y + s * 0.5))
                    star.addLine(to: CGPoint(x: c.x, y: c.y + s * 2)); star.addLine(to: CGPoint(x: c.x - s * 0.5, y: c.y + s * 0.5))
                    star.addLine(to: CGPoint(x: c.x - s * 2, y: c.y)); star.addLine(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.5)); star.closeSubpath()
                    ctx.opacity = sin(p * .pi) * (mood == .fresh ? 0.6 : 1)
                    ctx.fill(star, with: .color(i % 2 == 0 ? .white : color))
                }
            default: break
            }
        }
        .allowsHitTesting(false)
    }
}


private extension Color {
    /// A colour laid over another, for flat shading without a second draw.
    func blended(over base: Color) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black, b = NSColor(base).usingColorSpace(.sRGB) ?? .black
        let k = a.alphaComponent
        return Color(red: a.redComponent * k + b.redComponent * (1 - k), green: a.greenComponent * k + b.greenComponent * (1 - k),
                     blue: a.blueComponent * k + b.blueComponent * (1 - k))
    }
}
