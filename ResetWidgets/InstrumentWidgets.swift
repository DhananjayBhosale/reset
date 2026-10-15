import SwiftUI
import WidgetKit

/// Third set, from the instrument-style references: one instrument per tile.
struct InstrumentWidgets: WidgetBundle {
    var body: some Widget {
        GameBoyWidget()
        TickerWidget()
        ETAWidget()
        CalendarWidget()
    }
}

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
                // A fresh window has no reset time yet; the next message starts it, hence the nod.
                Text(d.map { $0.isReady(at: e.date) } ?? true ? "PRESS START" : "RESETS \(t(d?.target))")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
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
                    Text("API value").font(.system(size: 10)).foregroundStyle(label)
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
        // A fresh window is already here: say so, instead of a "--" arrival time and empty route ends.
        let ready = d?.isReady(at: e.date) ?? false
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                cap("NEXT WINDOW ARRIVES")
                Text(ready ? "Now" : t(d?.target)).font(.system(size: 38, weight: .regular).monospacedDigit()).foregroundStyle(.white)
                if ready {
                    Text("fresh window waiting").font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                } else if let d {
                    CountdownText(d: d, now: e.date).font(.system(size: 13).monospacedDigit()).foregroundStyle(.white.opacity(0.75)).environment(\.lookUsesTimerText, true)
                }
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
                    if ready {
                        Text("starts with your next message").font(.system(size: 10)).foregroundStyle(label)
                    } else {
                        Text(t(d?.windowStart)).font(.system(size: 10)).foregroundStyle(label)
                        Spacer()
                        Text(t(d?.resetsAt)).font(.system(size: 10)).foregroundStyle(label)
                    }
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
