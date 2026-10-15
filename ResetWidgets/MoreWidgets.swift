import SwiftUI
import WidgetKit

struct MoreWidgets: WidgetBundle {
    var body: some Widget {
        BoardSmallWidget()
        GaugeSmallWidget()
        SkySmallWidget()
        HoloSmallWidget()
        TodaySmallWidget()
        MascotSmallWidget()
        ValueMediumWidget()
        MonthLargeWidget()
    }
}

private func claudeCard(_ e: Entry) -> CardData? {
    guard let p = e.snap?.claude else { return nil }
    return CardData(id: p.id, name: p.name, color: W.color(p.id), windowStart: p.resetsAt?.addingTimeInterval(-5 * 3600),
                    resetsAt: p.resetsAt, ready: p.ready, blockedUntil: p.blockedUntil, used: p.used,
                    mascot: W.mascot(p.id, p, at: e.date))
}

private func hm(_ d: CardData, _ now: Date) -> String {
    if d.isReady(at: now) { return "READY" }
    guard let t = d.target else { return "--:--" }
    let s = max(0, Int(t.timeIntervalSince(now)))
    return String(format: "%02d:%02d", s / 3600, (s % 3600) / 60)
}

private func clock(_ d: Date?) -> String { d?.formatted(date: .omitted, time: .shortened) ?? "--" }

private struct Missing: View {
    var body: some View { Text("Open Reset").font(.system(size: 12)).foregroundStyle(W.dim) }
}

// MARK: Departure board (small)

struct BoardSmallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.small.board", provider: Provider()) { e in BoardSmall(e: e) }
            .configurationDisplayName("Departure board")
            .description("Claude's next window as an LED dot countdown.")
            .supportedFamilies([.systemSmall])
    }
}

struct BoardSmall: View {
    let e: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let d = claudeCard(e) {
                HStack {
                    Text("Next window").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                    Spacer()
                    Image(systemName: "airplane").font(.system(size: 10)).foregroundStyle(.black.opacity(0.5))
                }
                let t = hm(d, e.date)
                if t == "READY" {
                    DotMatrix(text: "READY", on: Color(red: 0.24, green: 0.23, blue: 0.85), off: .black.opacity(0.07)).frame(height: 34)
                } else {
                    DotMatrix(text: String(t.prefix(2)), on: Color(red: 0.24, green: 0.23, blue: 0.85), off: .black.opacity(0.07)).frame(height: 40)
                    DotMatrix(text: String(t.suffix(2)), on: Color(red: 0.24, green: 0.23, blue: 0.85), off: .black.opacity(0.07)).frame(height: 40)
                }
                Spacer(minLength: 0)
                Text("Claude · \(clock(d.target))").font(.system(size: 11)).foregroundStyle(.black.opacity(0.5))
            } else { Missing() }
        }
        .containerBackground(for: .widget) { Color(red: 0.96, green: 0.96, blue: 0.95) }
        .environment(\.colorScheme, .light)
    }
}

// MARK: Gauge (small)

struct GaugeSmallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.small.gauge", provider: Provider()) { e in GaugeSmall(e: e) }
            .configurationDisplayName("Gauge")
            .description("A watch-style gauge of Claude's window left.")
            .supportedFamilies([.systemSmall])
    }
}

struct GaugeSmall: View {
    let e: Entry
    var body: some View {
        Group {
            if let d = claudeCard(e) {
                let left = d.left(at: e.date) ?? 1
                ZStack {
                    Canvas { ctx, size in
                        let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2 - 2
                        let n = 48
                        for i in 0..<n {
                            let f = Double(i) / Double(n - 1)
                            let a = (-225 + 270 * f) * .pi / 180
                            var p = Path()
                            p.move(to: CGPoint(x: c.x + cos(a) * (r - 12), y: c.y + sin(a) * (r - 12)))
                            p.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                            let lit = f <= left
                            ctx.stroke(p, with: .color(lit ? (left > 0.2 ? Color(red: 0.96, green: 0.62, blue: 0.04) : .red) : .white.opacity(0.12)),
                                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        }
                    }
                    VStack(spacing: 0) {
                        Text("\(Int((left * 100).rounded()))%").font(.system(size: 30, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                        Text("left").font(.system(size: 10)).foregroundStyle(W.dim)
                        CountdownText(d: d, now: e.date, align: .center).font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.26)).padding(.top, 4)
                            .frame(width: 76)
                            .environment(\.lookUsesTimerText, true)
                    }
                }
            } else { Missing() }
        }
        .containerBackground(for: .widget) { Color(red: 0.07, green: 0.07, blue: 0.075) }
    }
}

// MARK: Sky (small)

struct SkySmallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.small.sky", provider: Provider()) { e in SkySmall(e: e) }
            .configurationDisplayName("Sky")
            .description("Day when the window is fresh, evening halfway, night at the limit.")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
    }
}

struct SkySmall: View {
    let e: Entry
    var body: some View {
        Group {
            if let d = claudeCard(e) {
                let left = d.left(at: e.date) ?? 1
                let dark = left <= 0.6
                ZStack(alignment: .topLeading) {
                    GeometryReader { g in
                        let w = g.size.width, h = g.size.height, a = Double.pi * left
                        Path { p in p.addArc(center: CGPoint(x: w / 2, y: h * 0.78), radius: w * 0.38, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false) }
                            .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                        Circle().fill(left > 0.25 ? Color(red: 1, green: 0.9, blue: 0.66) : Color(red: 0.9, green: 0.92, blue: 0.96))
                            .frame(width: 18, height: 18).shadow(color: .white, radius: left > 0.25 ? 12 : 4)
                            .position(x: w / 2 - cos(a) * w * 0.38, y: h * 0.78 - sin(a) * w * 0.38)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(left > 0.6 ? "Day" : left > 0.25 ? "Evening" : "Night").font(.system(size: 13, weight: .semibold))
                        Text("\(Int((left * 100).rounded()))% left").font(.system(size: 11)).opacity(0.75)
                        Spacer()
                        CountdownText(d: d, now: e.date).font(.system(size: 26, weight: .light).monospacedDigit())
                            .environment(\.lookUsesTimerText, true)
                    }
                    .foregroundStyle(dark ? Color.white : Color(red: 0.06, green: 0.19, blue: 0.31))
                    .padding(14)
                }
            } else { Missing() }
        }
        .containerBackground(for: .widget) {
            let left = claudeCard(e)?.left(at: e.date) ?? 1
            LinearGradient(colors: left > 0.6 ? [Color(red: 0.36, green: 0.64, blue: 0.91), Color(red: 0.75, green: 0.88, blue: 0.98)]
                           : left > 0.25 ? [Color(red: 0.42, green: 0.31, blue: 0.55), Color(red: 0.95, green: 0.6, blue: 0.29)]
                           : [Color(red: 0.02, green: 0.03, blue: 0.05), Color(red: 0.11, green: 0.13, blue: 0.2)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: Holo (small)

struct HoloSmallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.small.holo", provider: Provider()) { e in HoloSmall(e: e) }
            .configurationDisplayName("Holo card")
            .description("Claude's mascot as a trading card. Rarity rises with what's left.")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
    }
}

struct HoloSmall: View {
    let e: Entry
    var body: some View {
        Group {
            if let d = claudeCard(e) {
                let left = d.left(at: e.date) ?? 1
                let rarity = left > 0.8 ? "LEGENDARY" : left > 0.5 ? "RARE" : left > 0.2 ? "UNCOMMON" : "COMMON"
                ZStack {
                    AngularGradient(colors: ([.pink, .cyan, .mint, .yellow, .pink] as [Color]).map { $0.opacity(0.85) }, center: .center)
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: 0.06, green: 0.06, blue: 0.09)).padding(5)
                    VStack(spacing: 4) {
                        HStack {
                            Text("Claude").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            Spacer()
                            Text("HP \(Int((left * 100).rounded()))").font(.system(size: 11, weight: .heavy).monospacedDigit()).foregroundStyle(.white)
                        }
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [d.color.opacity(0.5), d.color.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                            d.mascot?.resizable().aspectRatio(contentMode: .fit).padding(4)
                        }
                        HStack {
                            Text(rarity).font(.system(size: 7, weight: .heavy)).tracking(0.8)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(LinearGradient(colors: [.pink, .cyan], startPoint: .leading, endPoint: .trailing)))
                                .foregroundStyle(.black)
                            Spacer()
                            CountdownText(d: d, now: e.date, align: .trailing).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                                .frame(width: 60, alignment: .trailing)
                                .environment(\.lookUsesTimerText, true)
                        }
                    }
                    .padding(13)
                }
            } else { Missing() }
        }
        .containerBackground(for: .widget) { Color.black }
    }
}

// MARK: Today (small): focus-timer barcode

struct TodaySmallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.small.today", provider: Provider()) { e in TodaySmall(e: e) }
            .configurationDisplayName("Today")
            .description("Today's windows as a barcode, with your activity hour by hour.")
            .supportedFamilies([.systemSmall])
    }
}

struct TodaySmall: View {
    let e: Entry
    var body: some View {
        let cal = Calendar.current
        let day = cal.startOfDay(for: e.date)
        let wins = (e.snap?.windows ?? []).filter { $0.end > day }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text("\(wins.count) window\(wins.count == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(W.dim)
            }
            if let d = claudeCard(e) {
                CountdownText(d: d, now: e.date).font(.system(size: 26, weight: .light).monospacedDigit()).foregroundStyle(.white)
                    .environment(\.lookUsesTimerText, true)
            }
            Canvas { ctx, size in
                let amber = W.color("claude")
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: size.height - 10), cornerRadius: 4), with: .color(.white.opacity(0.06)))
                for w in wins {
                    let x0 = size.width * CGFloat(max(w.start, day).timeIntervalSince(day) / 86400)
                    let x1 = size.width * CGFloat(min(w.end, day.addingTimeInterval(86400)).timeIntervalSince(day) / 86400)
                    let r = CGRect(x: x0 + 1, y: 0, width: max(2, x1 - x0 - 2), height: size.height - 10)
                    if w.autoStart { ctx.stroke(Path(roundedRect: r, cornerRadius: 4), with: .color(amber), lineWidth: 1.5) }
                    else { ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(amber.opacity(0.9))) }
                }
                let x = size.width * CGFloat(e.date.timeIntervalSince(day) / 86400)
                var p = Path(); p.move(to: CGPoint(x: x, y: -2)); p.addLine(to: CGPoint(x: x, y: size.height - 8))
                ctx.stroke(p, with: .color(.white), lineWidth: 1.5)
                // Activity dots under the bar, one column per hour.
                for (h, v) in (e.snap?.today ?? []).enumerated() where v > 0.02 {
                    let cx = size.width * (CGFloat(h) + 0.5) / 24
                    let n = v > 0.66 ? 3 : v > 0.33 ? 2 : 1
                    // Up to three dots stacked in the strip under the bar, so busier hours read as taller columns.
                    for k in 0..<n { ctx.fill(Path(ellipseIn: CGRect(x: cx - 1.5, y: size.height - 3.2 - CGFloat(k) * 3.2, width: 3, height: 3)), with: .color(amber.opacity(0.35 + 0.22 * Double(n)))) }
                }
            }
            .frame(height: 44)
        }
        .containerBackground(for: .widget) { Color(red: 0.07, green: 0.07, blue: 0.075) }
    }
}

// MARK: Mascot (small)

struct MascotSmallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.small.mascot", provider: Provider()) { e in MascotSmall(e: e) }
            .configurationDisplayName("Mascot")
            .description("Claude's mascot, saying how the window is going.")
            .supportedFamilies([.systemSmall])
    }
}

struct MascotSmall: View {
    let e: Entry
    var body: some View {
        VStack(spacing: 4) {
            if let d = claudeCard(e), let p = e.snap?.claude {
                let left = d.left(at: e.date) ?? 1
                Text(line(left, ready: d.isReady(at: e.date), blocked: p.blockedUntil.map { $0 > e.date } ?? false))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                d.mascot?.resizable().aspectRatio(contentMode: .fit).frame(height: 78)
                    .shadow(color: d.color.opacity(0.45), radius: 14)
                CountdownText(d: d, now: e.date, align: .center).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(W.dim)
                    .frame(width: 90)
                    .environment(\.lookUsesTimerText, true)
            } else { Missing() }
        }
        .containerBackground(for: .widget) {
            ZStack { Color(red: 0.06, green: 0.06, blue: 0.065); RadialGradient(colors: [W.color("claude").opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 100) }
        }
    }

    private func line(_ left: Double, ready: Bool, blocked: Bool) -> String {
        if blocked { return "Weekly limit. Nap time." }
        if ready { return "Fresh window. Go build." }
        if left > 0.65 { return "Plenty left. Keep going." }
        if left > 0.3 { return "Halfway there." }
        if left > 0.05 { return "Running low. Wrap up." }
        return "Out of juice. Back soon."
    }
}

// MARK: Value (medium)

struct ValueMediumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.medium.value", provider: Provider()) { e in ValueMedium(e: e) }
            .configurationDisplayName("Value")
            .description("What your Claude usage is worth at API prices this month.")
            .supportedFamilies([.systemMedium])
    }
}

struct ValueMedium: View {
    let e: Entry
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This month").font(.system(size: 12, weight: .medium)).foregroundStyle(W.dim)
                Spacer(minLength: 0)
                if let m = e.snap?.monthMultiple {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(String(format: m >= 100 ? "%.0f" : "%.1f", m)).font(.system(size: 52, weight: .light).monospacedDigit())
                        Text("×").font(.system(size: 22, weight: .light)).foregroundStyle(W.dim)
                    }
                    Text("\(money(e.snap?.monthCost ?? 0)) of API value").font(.system(size: 11)).foregroundStyle(W.dim)
                } else {
                    Text(money(e.snap?.monthCost ?? 0)).font(.system(size: 44, weight: .light).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                    Text("of API value").font(.system(size: 11)).foregroundStyle(W.dim)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text("cache saved").font(.system(size: 10)).foregroundStyle(W.dim)
                    Text(money(e.snap?.monthCacheSaved ?? 0)).font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color(red: 0.18, green: 0.9, blue: 0.65))
                }
            }
            .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 6) {
                Text("When you build").font(.system(size: 10)).foregroundStyle(W.dim)
                MiniHeat(grid: e.snap?.heatmap ?? [])
            }
        }
        .containerBackground(for: .widget) {
            ZStack { Color(red: 0.06, green: 0.06, blue: 0.065)
                RadialGradient(colors: [Color(red: 0.18, green: 0.9, blue: 0.65).opacity(0.25), .clear], center: .bottomLeading, startRadius: 0, endRadius: 200) }
        }
    }
}

struct MiniHeat: View {
    let grid: [[Double]]
    var body: some View {
        Canvas { ctx, size in
            guard !grid.isEmpty else { return }
            let rows = grid.count, gap: CGFloat = 2
            let w = (size.width - gap * 23) / 24, h = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            for r in 0..<rows { for c in 0..<min(24, grid[r].count) {
                let v = grid[r][c]
                ctx.fill(Path(roundedRect: CGRect(x: CGFloat(c) * (w + gap), y: CGFloat(r) * (h + gap), width: w, height: h), cornerRadius: 2),
                         with: .color(v < 0.02 ? .white.opacity(0.06) : W.color("claude").opacity(0.22 + 0.78 * sqrt(v))))
            } }
        }
    }
}

// MARK: Month (large)

struct MonthLargeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.large.month", provider: Provider()) { e in MonthLarge(e: e) }
            .configurationDisplayName("Month")
            .description("Your month with Claude: token mix, when you build, and what it was worth.")
            .supportedFamilies([.systemLarge])
    }
}

struct MonthLarge: View {
    let e: Entry
    var body: some View {
        let mix = e.snap?.monthMix ?? [0, 0, 0, 0]
        let total = max(1, mix.reduce(0, +))
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your month").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(tokens(e.snap?.monthTokens ?? 0) + " tokens").font(.system(size: 12).monospacedDigit()).foregroundStyle(W.dim)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if let m = e.snap?.monthMultiple {
                    Text(String(format: "%.1f", m)).font(.system(size: 54, weight: .light).monospacedDigit())
                    Text("×").font(.system(size: 22, weight: .light)).foregroundStyle(W.dim)
                } else {
                    Text(money(e.snap?.monthCost ?? 0)).font(.system(size: 54, weight: .light).monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(money(e.snap?.monthCacheSaved ?? 0)).font(.system(size: 17, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color(red: 0.18, green: 0.9, blue: 0.65))
                    Text("cache saved").font(.system(size: 10)).foregroundStyle(W.dim)
                }
            }
            Waffle(mix: mix).frame(height: 68)
            HStack(spacing: 12) {
                key(Color(red: 0.36, green: 0.55, blue: 1), "Cache read", mix[0], total)
                key(Color(red: 0.73, green: 0.51, blue: 1), "Write", mix[1], total)
                key(W.color("claude"), "Output", mix[2], total)
            }
            Text("When you build").font(.system(size: 11)).foregroundStyle(W.dim).padding(.top, 2)
            MiniHeat(grid: e.snap?.heatmap ?? []).frame(height: 70)
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { Color(red: 0.06, green: 0.06, blue: 0.065) }
    }

    private func key(_ c: Color, _ n: String, _ v: Int, _ t: Int) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8)
            Text(n).font(.system(size: 10)).foregroundStyle(W.dim)
            Text(String(format: Double(v) / Double(t) >= 0.1 ? "%.0f%%" : "%.1f%%", Double(v) / Double(t) * 100)).font(.system(size: 10, weight: .medium).monospacedDigit())
        }
    }

    private func tokens(_ n: Int) -> String {
        let d = Double(n)
        return d >= 1e9 ? String(format: "%.2fB", d / 1e9) : d >= 1e6 ? String(format: "%.1fM", d / 1e6) : String(format: "%.0fk", d / 1e3)
    }
}

struct Waffle: View {
    let mix: [Int]
    var body: some View {
        Canvas { ctx, size in
            let colors = [Color(red: 0.36, green: 0.55, blue: 1), Color(red: 0.73, green: 0.51, blue: 1), W.color("claude"), Color.white.opacity(0.85)]
            let total = max(1, mix.reduce(0, +))
            var cells: [Color] = []
            for (i, n) in mix.enumerated() where n > 0 { cells += Array(repeating: colors[i], count: max(1, Int((Double(n) / Double(total) * 100).rounded()))) }
            while cells.count > 100 { cells.remove(at: 0) }
            while cells.count < 100 { cells.insert(colors[0], at: 0) }
            let cols = 25, rows = 4, gap: CGFloat = 3
            let s = min((size.width - gap * CGFloat(cols - 1)) / CGFloat(cols), (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
            for (i, c) in cells.enumerated() {
                let r = CGRect(x: CGFloat(i % cols) * (s + gap), y: CGFloat(i / cols) * (s + gap), width: s, height: s)
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(c.opacity(i % 7 == 0 ? 0.75 : 1)))
            }
        }
    }
}
