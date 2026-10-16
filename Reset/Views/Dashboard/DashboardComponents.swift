import SwiftUI

enum Dash {
    static let card = Color(hex: 0x141414)
    static let line = Color.white.opacity(0.07)
    static let dim = Color.white.opacity(0.5)
    static let faint = Color.white.opacity(0.32)
    static let claude = Color(hex: 0xFF9F43)
    static let green = Color(hex: 0x2EE6A6)
    static let blue = Color(hex: 0x5B8CFF)
    static let violet = Color(hex: 0xB983FF)

    static func hero(_ size: CGFloat) -> Font { .system(size: size, weight: .light, design: .default).monospacedDigit() }
    static func num(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: size, weight: w).monospacedDigit() }
    static let title = Font.system(size: 15, weight: .medium)
    static let label = Font.system(size: 12)

    static func money(_ v: Double) -> String {
        if v >= 1000 { return "$" + NumberFormatter.localizedString(from: NSNumber(value: Int(v.rounded())), number: .decimal) }
        return String(format: "$%.2f", v)
    }

    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1e9 { return String(format: "%.2fB", d / 1e9) }
        if d >= 1e6 { return String(format: "%.1fM", d / 1e6) }
        if d >= 1e3 { return String(format: "%.1fk", d / 1e3) }
        return "\(n)"
    }

    static func duration(_ ms: Int) -> String {
        let s = ms / 1000, h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

/// A warm dark card with an optional soft light behind it, as in the references.
struct GlowCard<Content: View>: View {
    var glow: Color? = nil
    var glowAt: UnitPoint = .center
    var glowSize: CGFloat = 320
    var glowOpacity: Double = 0.55
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                ZStack {
                    Dash.card
                    if let glow {
                        GeometryReader { g in
                            RadialGradient(colors: [glow.opacity(glowOpacity), glow.opacity(glowOpacity * 0.35), .clear],
                                           center: glowAt, startRadius: 0, endRadius: glowSize)
                                .blur(radius: 30)
                                .frame(width: g.size.width, height: g.size.height)
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Dash.line, lineWidth: 1))
    }
}

struct CardHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Dash.title).foregroundStyle(.white)
            if let subtitle { Text(subtitle).font(Dash.label).foregroundStyle(Dash.dim) }
        }
    }
}

/// The 5-hour window as a sun path: dashed track, a lit arc for time elapsed, and a white "now" dot.
struct WindowArc: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 2.5

    var body: some View {
        Canvas { ctx, size in
            // The "now" dot is sized for the hero; in the sidebar's 22-point arc it covered the whole arc, so small
            // arcs get a dot just wider than their line and room for it.
            let small = min(size.width / 2, size.height) < 30
            let dot: CGFloat = small ? lineWidth * 1.4 : 6, halo: CGFloat = small ? lineWidth * 2.2 : 11
            let r = small ? min(size.width / 2 - halo, size.height - halo - 2) : min(size.width / 2 - 6, size.height - 8)
            let c = CGPoint(x: size.width / 2, y: size.height - 2)
            func pt(_ t: Double) -> CGPoint { CGPoint(x: c.x - r * cos(.pi * t), y: c.y - r * sin(.pi * t)) }
            var track = Path()
            track.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            ctx.stroke(track, with: .color(.white.opacity(0.16)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 6]))
            let p = min(1, max(0, progress))
            guard p > 0 else { return }
            var lit = Path()
            lit.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(180 + 180 * p), clockwise: false)
            ctx.stroke(lit, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            let d = pt(p)
            ctx.fill(Path(ellipseIn: CGRect(x: d.x - halo, y: d.y - halo, width: halo * 2, height: halo * 2)), with: .color(color.opacity(0.25)))
            ctx.fill(Path(ellipseIn: CGRect(x: d.x - dot, y: d.y - dot, width: dot * 2, height: dot * 2)), with: .color(.white))
        }
    }
}

/// Limit used, drawn as a scale: dark when there is room, amber, then red as the window runs out.
struct BurnBar: View {
    var fraction: Double
    var height: CGFloat = 12
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.6))
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0x1a1208), Color(hex: 0x6b4a1a), Dash.claude, Color(hex: 0xFF5C3A)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: g.size.width * min(1, max(0, fraction)))
                    .mask(alignment: .leading) { Capsule().frame(width: g.size.width) }
            }
        }
        .frame(height: height)
    }
}

/// Every 5-hour window of the last week as a barcode: solid when you opened it, outlined when
/// auto-start did, with a red tip when the limit was hit. A white line marks now.
struct WindowBarcode: View {
    let windows: [UsageWindow]
    var days: Int = 7
    var showLabels = true
    var rowHeight: CGFloat = 22

    var body: some View {
        Canvas { ctx, size in
            let cal = Calendar.current
            let labelW: CGFloat = showLabels ? 44 : 0
            let hoursH: CGFloat = showLabels ? 18 : 0
            let plotW = size.width - labelW
            let rowGap = (size.height - hoursH - CGFloat(days) * rowHeight) / CGFloat(max(1, days - 1))
            let today = cal.startOfDay(for: Date())
            let df = DateFormatter(); df.dateFormat = "EEE"
            for i in 0..<days {
                let day = cal.date(byAdding: .day, value: i - (days - 1), to: today)!
                let y = CGFloat(i) * (rowHeight + rowGap)
                if showLabels {
                    ctx.draw(Text(df.string(from: day)).font(.system(size: 11)).foregroundColor(Dash.dim),
                             at: CGPoint(x: 0, y: y + rowHeight / 2), anchor: .leading)
                }
                let row = CGRect(x: labelW, y: y, width: plotW, height: rowHeight)
                ctx.fill(Path(roundedRect: row, cornerRadius: 5), with: .color(Color.white.opacity(0.04)))
                let dayEnd = day.addingTimeInterval(86400)
                for w in windows where w.end > day && w.start < dayEnd {
                    let s = max(w.start, day), e = min(w.end, dayEnd)
                    let x0 = labelW + plotW * CGFloat(s.timeIntervalSince(day) / 86400)
                    let x1 = labelW + plotW * CGFloat(e.timeIntervalSince(day) / 86400)
                    let r = CGRect(x: x0 + 1, y: y + 1, width: max(2, x1 - x0 - 2), height: rowHeight - 2)
                    let shape = Path(roundedRect: r, cornerRadius: 5)
                    if w.autoStart {
                        ctx.stroke(shape, with: .color(Dash.claude), lineWidth: 1.5)
                    } else {
                        ctx.fill(shape, with: .color(Dash.claude.opacity(0.85)))
                    }
                    if w.hitLimit, e == w.end {
                        ctx.fill(Path(roundedRect: CGRect(x: r.maxX - 6, y: r.minY, width: 6, height: r.height), cornerRadius: 2),
                                 with: .color(Color(hex: 0xFF5C3A)))
                    }
                }
                if cal.isDateInToday(day) {
                    let x = labelW + plotW * CGFloat(Date().timeIntervalSince(day) / 86400)
                    var p = Path(); p.move(to: CGPoint(x: x, y: y - 4)); p.addLine(to: CGPoint(x: x, y: y + rowHeight + 4))
                    ctx.stroke(p, with: .color(.white), lineWidth: 1.5)
                }
            }
            if showLabels {
                let y = size.height - 6
                for (h, label) in [0, 6, 12, 18].map({ ($0, Fmt.hourLabel($0)) }) {
                    ctx.draw(Text(label).font(.system(size: 10)).foregroundColor(Dash.faint),
                             at: CGPoint(x: labelW + plotW * CGFloat(h) / 24, y: y), anchor: .leading)
                }
            }
        }
    }
}

/// 100 squares, each 1% of tokens, coloured by kind.
struct TokenGrid: View {
    let mix: UsageStore.Mix
    var body: some View {
        Canvas { ctx, size in
            let parts: [(Color, Int)] = [(Dash.blue, mix.cacheRead), (Dash.violet, mix.cacheWrite), (Dash.claude, mix.output), (.white.opacity(0.85), mix.input)]
            let total = max(1, mix.total)
            var cells: [Color] = []
            for (c, n) in parts {
                let k = n > 0 ? max(1, Int((Double(n) / Double(total) * 100).rounded())) : 0
                cells += Array(repeating: c, count: k)
            }
            while cells.count > 100 { if let i = cells.firstIndex(of: Dash.blue) { cells.remove(at: i) } else { cells.removeLast() } }
            // Topping up with blue rounds a real mix to 100; with no tokens at all it painted "100% cache read".
            let empty = Color.white.opacity(0.06)
            while cells.count < 100 { cells.insert(mix.total > 0 ? Dash.blue : empty, at: 0) }
            let cols = 20, gap: CGFloat = 3
            let side = (size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            for (i, c) in cells.enumerated() {
                let r = CGRect(x: CGFloat(i % cols) * (side + gap), y: CGFloat(i / cols) * (side + gap), width: side, height: side)
                let shade = c == Dash.blue ? 0.55 + 0.45 * Double((i * 37) % 11) / 10 : 1
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(c.opacity(shade)))
            }
        }
        .aspectRatio(20 / 5, contentMode: .fit)
    }
}

struct Heatmap: View {
    let grid: [[Double]]
    var color: Color = Dash.claude
    var body: some View {
        Canvas { ctx, size in
            let rows = grid.count, cols = 24, gap: CGFloat = 3
            let w = (size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let h = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            let maxV = grid.flatMap { $0 }.max() ?? 0
            for r in 0..<rows { for c in 0..<cols {
                let v = maxV > 0 ? grid[r][c] / maxV : 0
                let rect = CGRect(x: CGFloat(c) * (w + gap), y: CGFloat(r) * (h + gap), width: w, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3),
                         with: .color(v < 0.02 ? Color.white.opacity(0.06) : color.opacity(0.22 + 0.78 * sqrt(v))))
            } }
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var tint: Color = .white
    var body: some View {
        HStack {
            Text(label).font(Dash.label).foregroundStyle(Dash.dim)
            Spacer()
            Text(value).font(Dash.num(13)).foregroundStyle(tint)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Dash.line).frame(height: 1) }
    }
}

struct LegendDot: View {
    let color: Color
    let text: String
    var outlined = false
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(outlined ? Color.clear : color)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(color, lineWidth: outlined ? 1.5 : 0))
                .frame(width: 10, height: 10)
            Text(text).font(Dash.label).foregroundStyle(Dash.dim)
        }
    }
}
