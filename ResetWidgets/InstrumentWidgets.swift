import SwiftUI
import WidgetKit

/// Third set, from the instrument-style references: one instrument per tile.
struct InstrumentWidgets: WidgetBundle {
    var body: some Widget {
        DialWidget()
        RemainWidget()
        TimesWidget()
        SpendWidget()
        GameBoyWidget()
        TickerWidget()
        ETAWidget()
        ProjectsWidget()
        CalendarWidget()
    }
}

private let ink = Color(red: 0.11, green: 0.11, blue: 0.12)
private let panel = Color(red: 0.13, green: 0.13, blue: 0.145)
private let amber = Color(red: 1, green: 0.62, blue: 0.26)
private let label = Color.white.opacity(0.5)

private func card(_ e: Entry) -> CardData? {
    guard let p = e.snap?.claude else { return nil }
    return CardData(id: p.id, name: p.name, color: amber, windowStart: p.resetsAt?.addingTimeInterval(-5 * 3600),
                    resetsAt: p.resetsAt, ready: p.ready, blockedUntil: p.blockedUntil, used: p.used,
                    mascot: W.mascot(p.id, p, at: e.date))
}
private func t(_ d: Date?) -> String { d?.formatted(date: .omitted, time: .shortened) ?? "--" }
private func cap(_ s: String) -> some View { Text(s).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(label) }

// MARK: Dial: the 5-hour window as a compass

struct DialWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.i.dial", provider: Provider()) { e in Dial(e: e) }
            .configurationDisplayName("Dial")
            .description("The 5-hour window as a compass dial, with a needle at now.")
            .supportedFamilies([.systemSmall])
    }
}

struct Dial: View {
    let e: Entry
    var body: some View {
        let d = card(e)
        let p = d?.elapsed(at: e.date) ?? 0
        ZStack {
            Circle().fill(Color(red: 0.2, green: 0.2, blue: 0.22))
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2), r = size.width / 2
                for i in 0..<60 {
                    let a = Double(i) / 60 * 2 * .pi - .pi / 2
                    let long = i % 12 == 0
                    var path = Path()
                    path.move(to: CGPoint(x: c.x + cos(a) * (r - (long ? 9 : 5)), y: c.y + sin(a) * (r - (long ? 9 : 5))))
                    path.addLine(to: CGPoint(x: c.x + cos(a) * (r - 1), y: c.y + sin(a) * (r - 1)))
                    ctx.stroke(path, with: .color(.white.opacity(long ? 0.9 : 0.35)), lineWidth: long ? 2 : 1)
                }
                for h in 0..<5 {
                    let a = Double(h) / 5 * 2 * .pi - .pi / 2
                    ctx.draw(Text("\(h)h").font(.system(size: 11, weight: .semibold)).foregroundColor(.white),
                             at: CGPoint(x: c.x + cos(a) * (r - 22), y: c.y + sin(a) * (r - 22)))
                }
                // Elapsed sweep and needle.
                var sweep = Path()
                sweep.addArc(center: c, radius: r * 0.52, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * p), clockwise: false)
                ctx.stroke(sweep, with: .color(amber.opacity(0.85)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                let a = p * 2 * .pi - .pi / 2
                var needle = Path()
                needle.move(to: c); needle.addLine(to: CGPoint(x: c.x + cos(a) * (r - 30), y: c.y + sin(a) * (r - 30)))
                ctx.stroke(needle, with: .color(.red), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(.white))
            }
            if let d {
                CountdownText(d: d, now: e.date, align: .center).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                    .environment(\.lookUsesTimerText, true)
                    .frame(width: 70)
                    .offset(y: 22)
            }
        }
        .padding(2)
        .containerBackground(for: .widget) { ink }
    }
}

// MARK: Remain: semicircle gauge

struct RemainWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.i.remain", provider: Provider()) { e in Remain(e: e) }
            .configurationDisplayName("Remain")
            .description("How much of Claude's window remains, on a half gauge.")
            .supportedFamilies([.systemSmall])
    }
}

struct Remain: View {
    let e: Entry
    var body: some View {
        let d = card(e)
        let left = d?.left(at: e.date) ?? 1
        VStack(alignment: .leading, spacing: 6) {
            cap("CLAUDE")
            ZStack(alignment: .bottom) {
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height), r = min(size.width / 2, size.height) - 8
                    var bg = Path(); bg.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                    ctx.stroke(bg, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                    var fg = Path(); fg.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(180 + 180 * left), clockwise: false)
                    ctx.stroke(fg, with: .color(left > 0.2 ? Color(red: 0.42, green: 0.39, blue: 0.96) : .red), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                    let a = Double.pi * (1 + left)
                    let tip = CGPoint(x: c.x + cos(a) * (r - 13), y: c.y + sin(a) * (r - 13))
                    var tri = Path(); tri.addEllipse(in: CGRect(x: tip.x - 3.5, y: tip.y - 3.5, width: 7, height: 7))
                    ctx.fill(tri, with: .color(.white))
                }
                Text("REMAIN").font(.system(size: 10, weight: .semibold)).foregroundStyle(label).padding(.bottom, 2)
            }
            .frame(height: 64)
            Text("\(Int((left * 100).rounded()))%").font(.system(size: 30, weight: .regular).monospacedDigit()).foregroundStyle(.white)
            if let d { CountdownText(d: d, now: e.date).font(.system(size: 11).monospacedDigit()).foregroundStyle(label).environment(\.lookUsesTimerText, true) }
        }
        .containerBackground(for: .widget) { panel }
    }
}

// MARK: Window times: sunrise / sunset

struct TimesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.i.times", provider: Provider()) { e in Times(e: e) }
            .configurationDisplayName("Window times")
            .description("When the current window started and when it resets, like sunrise and sunset.")
            .supportedFamilies([.systemSmall])
    }
}

struct Times: View {
    let e: Entry
    var body: some View {
        let d = card(e)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 5)
                    Circle().trim(from: 0, to: d?.elapsed(at: e.date) ?? 0).stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text(d.map { "\(Int((($0.left(at: e.date) ?? 1) * 100).rounded()))" } ?? "--").font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(label)
                }
                .frame(width: 46, height: 46)
                Spacer()
                d?.mascot?.resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40)
            }
            Spacer(minLength: 0)
            row("sunrise", t(d?.windowStart))
            row("sunset", t(d?.resetsAt))
            Text("Claude window").font(.system(size: 10)).foregroundStyle(label)
        }
        .containerBackground(for: .widget) { panel }
    }
    private func row(_ icon: String, _ v: String) -> some View {
        HStack {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(v).font(.system(size: 18, weight: .regular).monospacedDigit()).foregroundStyle(.white)
        }
    }
}

// MARK: Spend bars

struct SpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.i.spend", provider: Provider()) { e in Spend(e: e) }
            .configurationDisplayName("Spend")
            .description("API value this week, day by day, against last week.")
            .supportedFamilies([.systemSmall])
    }
}

struct Spend: View {
    let e: Entry
    var body: some View {
        let days = e.snap?.dailyCost ?? Array(repeating: 0, count: 14)
        let last = Array(days.suffix(7)), prev = Array(days.prefix(7))
        let a = last.reduce(0, +), b = prev.reduce(0, +)
        let change = b > 0 ? (a - b) / b * 100 : 0
        VStack(alignment: .leading, spacing: 4) {
            cap("API VALUE")
            Text(money(a)).font(.system(size: 30, weight: .regular).monospacedDigit()).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text("last 7 days").font(.system(size: 11)).foregroundStyle(label)
            Text(String(format: "%@%.0f%%", change >= 0 ? "+" : "", change))
                .font(.system(size: 11, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(change >= 0 ? Color(red: 0.2, green: 0.7, blue: 0.35) : Color(red: 0.85, green: 0.3, blue: 0.3)))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Canvas { ctx, size in
                let all = prev + last, m = max(0.01, all.max() ?? 1)
                let w = (size.width - 13 * 3) / 14
                for (i, v) in all.enumerated() {
                    let h = max(2, size.height * v / m)
                    ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * (w + 3), y: size.height - h, width: w, height: h), cornerRadius: 1.5),
                             with: .color(i >= 7 ? Color(red: 0.25, green: 0.8, blue: 0.4) : .white.opacity(0.25)))
                }
            }
            .frame(height: 30)
        }
        .containerBackground(for: .widget) { panel }
    }
}

// MARK: Game Boy

struct GameBoyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.i.gameboy", provider: Provider()) { e in GameBoy(e: e) }
            .configurationDisplayName("Game Boy")
            .description("The countdown on a handheld's LCD.")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
    }
}

struct GameBoy: View {
    let e: Entry
    var body: some View {
        let d = card(e)
        let lcd = Color(red: 0.62, green: 0.74, blue: 0.45), lcdInk = Color(red: 0.15, green: 0.22, blue: 0.1)
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("CLAUDE").font(.system(size: 8, weight: .heavy, design: .monospaced))
                    Spacer()
                    Text(d.map { "\(Int((($0.left(at: e.date) ?? 1) * 100).rounded()))%" } ?? "--").font(.system(size: 8, weight: .heavy, design: .monospaced))
                }
                Group {
                    if let d, !d.isReady(at: e.date), let tt = d.target {
                        Text(timerInterval: e.date...tt, countsDown: true, showsHours: true)
                    } else { Text("READY") }
                }
                .font(.system(size: 26, weight: .bold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
                Text("RESETS \(t(d?.target))").font(.system(size: 8, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(lcdInk)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(lcd))
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.25, green: 0.25, blue: 0.3)))
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(.black.opacity(0.8)).frame(width: 30, height: 9)
                    RoundedRectangle(cornerRadius: 2).fill(.black.opacity(0.8)).frame(width: 9, height: 30)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Color(red: 0.75, green: 0.15, blue: 0.35)).frame(width: 14, height: 14).offset(y: 5)
                    Circle().fill(Color(red: 0.75, green: 0.15, blue: 0.35)).frame(width: 14, height: 14).offset(y: -4)
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(12)
        .containerBackground(for: .widget) { Color(red: 0.98, green: 0.78, blue: 0.2) }
        .environment(\.colorScheme, .light)
    }
}

// MARK: Ticker: today's spend like a stock

struct TickerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.i.ticker", provider: Provider()) { e in Ticker(e: e) }
            .configurationDisplayName("Ticker")
            .description("Today's Claude spend as a live chart, against yesterday.")
            .supportedFamilies([.systemMedium])
    }
}

struct Ticker: View {
    let e: Entry
    var body: some View {
        let today = e.snap?.todayCumulative ?? Array(repeating: 0, count: 24)
        let yest = e.snap?.yesterdayCumulative ?? Array(repeating: 0, count: 24)
        let hour = Calendar.current.component(.hour, from: e.date)
        let now = today[min(23, hour)], thenY = yest[min(23, hour)]
        let diff = now - thenY
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                if let m = e.snap?.claude.flatMap({ W.mascot("claude", $0, at: e.date) }) { m.resizable().aspectRatio(contentMode: .fit).frame(width: 30, height: 30) }
                VStack(alignment: .leading, spacing: 0) {
                    Text("CLD").font(.system(size: 10)).foregroundStyle(label)
                    Text("Claude today").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("updated").font(.system(size: 10)).foregroundStyle(label)
                    Text(e.snap.map { $0.updated.formatted(date: .omitted, time: .shortened) } ?? "--").font(.system(size: 13)).foregroundStyle(.white)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(money2(now)).font(.system(size: 30, weight: .regular).monospacedDigit()).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: "%@$%.2f", diff >= 0 ? "+" : "-", abs(diff))).font(.system(size: 11, weight: .medium)).foregroundStyle(diff >= 0 ? .green : .red)
                    Text("vs this time yesterday").font(.system(size: 9)).foregroundStyle(label)
                }
            }
            Canvas { ctx, size in
                let m = max(0.01, (today + yest).max() ?? 1)
                func pt(_ i: Int, _ v: Double) -> CGPoint { CGPoint(x: size.width * CGFloat(i) / 23, y: size.height * (1 - CGFloat(v / m))) }
                var y = Path(); for (i, v) in yest.enumerated() { i == 0 ? y.move(to: pt(i, v)) : y.addLine(to: pt(i, v)) }
                ctx.stroke(y, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                var line = Path(), fill = Path()
                fill.move(to: CGPoint(x: 0, y: size.height))
                for i in 0...min(23, hour) { let p = pt(i, today[i]); i == 0 ? line.move(to: p) : line.addLine(to: p); fill.addLine(to: p) }
                fill.addLine(to: CGPoint(x: pt(min(23, hour), 0).x, y: size.height)); fill.closeSubpath()
                ctx.fill(fill, with: .linearGradient(Gradient(colors: [Color.green.opacity(0.35), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                ctx.stroke(line, with: .color(.green), lineWidth: 2)
            }
        }
        .containerBackground(for: .widget) { Color.black }
    }
}

private func money2(_ v: Double) -> String { v >= 1000 ? money(v) : String(format: "$%.2f", v) }

// MARK: ETA

struct ETAWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.i.eta", provider: Provider()) { e in ETA(e: e) }
            .configurationDisplayName("Arrival")
            .description("When your next Claude window arrives, with the window drawn as a route.")
            .supportedFamilies([.systemMedium])
    }
}

struct ETA: View {
    let e: Entry
    var body: some View {
        let d = card(e)
        let left = d?.left(at: e.date) ?? 1
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                cap("NEXT WINDOW ARRIVES")
                Text(t(d?.target)).font(.system(size: 38, weight: .regular).monospacedDigit()).foregroundStyle(.white)
                if let d { CountdownText(d: d, now: e.date).font(.system(size: 13).monospacedDigit()).foregroundStyle(.white.opacity(0.75)).environment(\.lookUsesTimerText, true) }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text("WINDOW").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(red: 0.3, green: 0.6, blue: 1))
                    Text("\(Int((left * 100).rounded()))% left").font(.system(size: 11)).foregroundStyle(label)
                }
                // The route: green for time with plenty left, through yellow and red as the limit nears.
                GeometryReader { g in
                    HStack(spacing: 3) {
                        ForEach(0..<14, id: \.self) { i in
                            let f = Double(i) / 13
                            RoundedRectangle(cornerRadius: 2)
                                .fill(f < 0.5 ? Color.green : f < 0.8 ? Color.yellow : Color.red)
                                .opacity(f <= 1 - left ? 1 : 0.25)
                        }
                    }
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.white).frame(width: 2, height: 16).offset(x: g.size.width * (1 - left) - 1)
                    }
                }
                .frame(height: 8)
                HStack {
                    Text(t(d?.windowStart)).font(.system(size: 10)).foregroundStyle(label)
                    Spacer()
                    Text(t(d?.resetsAt)).font(.system(size: 10)).foregroundStyle(label)
                }
            }
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)).frame(width: 52, height: 52)
                d?.mascot?.resizable().aspectRatio(contentMode: .fit).frame(width: 44, height: 44)
            }
        }
        .containerBackground(for: .widget) { panel }
    }
}

// MARK: Projects: bubbles

struct ProjectsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.i.projects", provider: Provider()) { e in Projects(e: e) }
            .configurationDisplayName("Projects")
            .description("Where your Claude usage went this month, as bubbles.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct Projects: View {
    let e: Entry
    var body: some View {
        let list = e.snap?.projects ?? []
        let total = list.reduce(0) { $0 + $1.cost }
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                cap("THIS MONTH")
                Text(money(e.snap?.monthCost ?? total)).font(.system(size: 30, weight: .regular).monospacedDigit()).foregroundStyle(.white)
                Spacer(minLength: 4)
                ForEach(Array(list.prefix(3).enumerated()), id: \.offset) { i, p in
                    HStack(spacing: 5) {
                        Circle().fill(Self.colors[i % Self.colors.count]).frame(width: 7, height: 7)
                        Text(p.name).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(money(p.cost)).font(.system(size: 11).monospacedDigit()).foregroundStyle(label)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Canvas { ctx, size in
                guard let maxC = list.first?.cost, maxC > 0 else { return }
                // Greedy circle packing: biggest in the middle, each next one spirals out to the first free spot.
                let top = Array(list.prefix(6)), sum = max(0.01, top.reduce(0) { $0 + $1.cost })
                var placed: [(CGPoint, CGFloat)] = []
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for (i, p) in list.prefix(6).enumerated() {
                    // Bubbles share about half the tile's area, in proportion to cost.
                    let r = min(min(size.width, size.height) / 2 - 2, sqrt(0.5 * size.width * size.height * CGFloat(p.cost / sum) / .pi))
                    var pos = center
                    if !placed.isEmpty {
                        var found = false
                        var step = 0.0
                        while !found && step < 400 {
                            let ang = step * 0.35, dist = 2 + step * 0.9
                            let c = CGPoint(x: center.x + cos(ang) * dist, y: center.y + sin(ang) * dist * 0.8)
                            let inside = c.x - r >= 0 && c.x + r <= size.width && c.y - r >= 0 && c.y + r <= size.height
                            if inside && placed.allSatisfy({ hypot($0.0.x - c.x, $0.0.y - c.y) >= $0.1 + r + 3 }) { pos = c; found = true }
                            step += 1
                        }
                        if !found { continue }
                    }
                    placed.append((pos, r))
                    ctx.fill(Path(ellipseIn: CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)), with: .color(Self.colors[i % Self.colors.count]))
                    if i == 0 { ctx.draw(Text(money(p.cost)).font(.system(size: 12, weight: .semibold)).foregroundColor(.white), at: pos) }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .containerBackground(for: .widget) { panel }
    }
    static let colors: [Color] = [Color(red: 0.3, green: 0.55, blue: 1), Color(red: 1, green: 0.74, blue: 0.2), Color(red: 0.62, green: 0.4, blue: 1),
                                  Color(red: 1, green: 0.42, blue: 0.4), Color(red: 0.25, green: 0.8, blue: 0.55), Color(red: 0.95, green: 0.95, blue: 0.95)]
}

// MARK: Calendar: cozy cream month

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.i.calendar", provider: Provider()) { e in MonthCalendar(e: e) }
            .configurationDisplayName("Calendar")
            .description("Your month: which days you built, and the days you hit the limit.")
            .supportedFamilies([.systemMedium])
    }
}

struct MonthCalendar: View {
    let e: Entry
    var body: some View {
        let cal = Calendar.current
        let days = e.snap?.monthDays ?? []
        let limits = Set(e.snap?.limitDays ?? [])
        let first = cal.date(from: cal.dateComponents([.year, .month], from: e.date))!
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        let today = cal.component(.day, from: e.date)
        let maxV = max(0.01, days.max() ?? 1)
        let creamInk = Color(red: 0.22, green: 0.2, blue: 0.17)
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.date.formatted(.dateTime.month(.wide))).font(.system(size: 12, weight: .semibold)).foregroundStyle(creamInk.opacity(0.6))
                Text("\(today)").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(creamInk)
                Spacer(minLength: 0)
                Text(money(days.reduce(0, +))).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(creamInk)
                Text("built this month").font(.system(size: 10)).foregroundStyle(creamInk.opacity(0.55))
                HStack(spacing: 4) {
                    Circle().fill(Color(red: 0.88, green: 0.32, blue: 0.3)).frame(width: 6, height: 6)
                    Text("\(limits.count) limit days").font(.system(size: 10)).foregroundStyle(creamInk.opacity(0.55))
                }
            }
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { Text($0).font(.system(size: 8, weight: .bold)).foregroundStyle(creamInk.opacity(0.4)).frame(maxWidth: .infinity) }
                }
                let cells = lead + days.count
                let rows = Int(ceil(Double(cells) / 7))
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { c in
                            let idx = r * 7 + c - lead
                            if idx >= 0 && idx < days.count {
                                let v = days[idx], day = idx + 1
                                ZStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(v > 0 ? amber.opacity(0.25 + 0.75 * sqrt(v / maxV)) : creamInk.opacity(0.06))
                                    if day == today { RoundedRectangle(cornerRadius: 4).stroke(creamInk, lineWidth: 1.5) }
                                    Text("\(day)").font(.system(size: 8, weight: .semibold)).foregroundStyle(v / maxV > 0.5 ? .white : creamInk.opacity(0.7))
                                    if limits.contains(day) {
                                        Circle().fill(Color(red: 0.88, green: 0.32, blue: 0.3)).frame(width: 4, height: 4)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(1.5)
                                    }
                                }
                                .frame(maxWidth: .infinity).aspectRatio(1.25, contentMode: .fit)
                            } else {
                                Color.clear.frame(maxWidth: .infinity).aspectRatio(1.25, contentMode: .fit)
                            }
                        }
                    }
                }
            }
        }
        .containerBackground(for: .widget) { Color(red: 0.97, green: 0.94, blue: 0.86) }
        .environment(\.colorScheme, .light)
    }
}
