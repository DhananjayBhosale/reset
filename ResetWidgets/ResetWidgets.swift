import SwiftUI
import WidgetKit

@main
struct ResetWidgets: WidgetBundle {
    var body: some Widget {
        ClaudeWidget()
        FuseWidget()
        WeekWidget()
        MoreWidgets().body
        InstrumentWidgets().body
    }
}

// MARK: Timeline

struct Entry: TimelineEntry {
    var date: Date
    var snap: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snap: WidgetSnapshot.load() ?? .sample))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snap = WidgetSnapshot.load()
        let now = Date()
        // Countdowns tick on their own (timer text). New entries just re-evaluate state at each reset and every 15 min;
        // the app also asks WidgetKit to reload whenever its numbers change.
        var dates = [now]
        for p in snap?.providers ?? [] { if let r = p.resetsAt, r > now, r < now.addingTimeInterval(6 * 3600) { dates.append(r.addingTimeInterval(1)) } }
        // One entry a minute for the next hour, so drawn countdowns (LED dots, gauges) stay current.
        dates += stride(from: 1.0, through: 60, by: 1).map { now.addingTimeInterval($0 * 60) }
        let entries = Set(dates).sorted().map { Entry(date: $0, snap: snap) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

// MARK: Look

enum W {
    static func color(_ id: String) -> Color {
        switch id {
        case "claude": return Color(red: 1, green: 0.62, blue: 0.26)
        case "codex": return Color(red: 0.18, green: 0.9, blue: 0.65)
        case "gemini": return Color(red: 0.36, green: 0.55, blue: 1)
        case "antigravity": return Color(red: 0.24, green: 0.61, blue: 1)
        default: return .pink
        }
    }
    static let dim = Color.white.opacity(0.5)
    static let bg = Color(red: 0.06, green: 0.06, blue: 0.065)

    static func mascot(_ id: String, _ p: WidgetSnapshot.Provider, at date: Date) -> Image? {
        let mood: String
        if let b = p.blockedUntil, b > date { mood = "asleep" }
        else if p.ready || !p.available { mood = "fresh" }
        else if let u = p.used { mood = u >= 99.5 ? "asleep" : u >= 70 ? "tired" : u >= 35 ? "focused" : "fresh" }
        else { mood = "focused" }
        guard let url = Bundle.main.url(forResource: "\(id)-\(mood)", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: img)
    }

    /// Health left, 0...1, or nil when usage is unknown.
    static func health(_ p: WidgetSnapshot.Provider, at date: Date) -> Double? {
        if let b = p.blockedUntil, b > date { return 0 }
        if p.ready { return 1 }
        if let r = p.resetsAt, r <= date { return 1 }
        if let u = p.used { return max(0, 1 - u / 100) }
        return nil
    }

    static func isReady(_ p: WidgetSnapshot.Provider, at date: Date) -> Bool {
        p.ready || (p.resetsAt.map { $0 <= date } ?? false)
    }

    /// A "Start now" is in progress: pressed within the last 4 minutes (a run's limit is 3) and still no window.
    static func isStarting(_ s: WidgetSnapshot?, at date: Date) -> Bool {
        guard let t = s?.startingAt, date.timeIntervalSince(t) < 240, let p = s?.claude else { return false }
        return isReady(p, at: date)
    }
}

struct Segments: View {
    let health: Double?
    let color: Color
    var count = 10
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                let lit = health.map { Double(i) < ($0 * Double(count)).rounded(.up) } ?? true
                Capsule().fill(lit ? (health == nil ? color.opacity(0.3) : tint) : Color.white.opacity(0.1)).frame(height: 5)
            }
        }
    }
    private var tint: Color {
        guard let h = health else { return color }
        return h > 0.5 ? color : h > 0.2 ? Color(red: 1, green: 0.69, blue: 0.24) : Color(red: 1, green: 0.29, blue: 0.37)
    }
}

struct Countdown: View {
    let p: WidgetSnapshot.Provider
    let date: Date
    var size: CGFloat
    var align: TextAlignment = .leading
    var body: some View {
        if let b = p.blockedUntil, b > date {
            Text(timerInterval: date...b, countsDown: true).font(.system(size: size, weight: .light).monospacedDigit())
                .multilineTextAlignment(align)
        } else if W.isReady(p, at: date) {
            Text("ready").font(.system(size: size * 0.8, weight: .regular)).foregroundStyle(W.color(p.id))
        } else if let r = p.resetsAt {
            Text(timerInterval: date...r, countsDown: true, showsHours: true).font(.system(size: size, weight: .light).monospacedDigit())
                .multilineTextAlignment(align)
        } else {
            Text("--").font(.system(size: size, weight: .light)).foregroundStyle(W.dim)
        }
    }
}

// MARK: Small: Claude

struct ClaudeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.claude", provider: Provider()) { e in ClaudeSmall(e: e) }
            .configurationDisplayName("Claude window")
            .description("Countdown to your next Claude window, with the mascot's health bar.")
            .supportedFamilies([.systemSmall])
    }
}

struct ClaudeSmall: View {
    let e: Entry
    var body: some View {
        let p = e.snap?.claude
        ZStack(alignment: .topLeading) {
            if let p, let img = W.mascot("claude", p, at: e.date) {
                img.resizable().aspectRatio(contentMode: .fit).frame(width: 82, height: 82)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 8, y: -6)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude").font(.system(size: 12, weight: .medium)).foregroundStyle(W.dim)
                Spacer()
                if let p {
                    Countdown(p: p, date: e.date, size: 30).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                    Text(subtitle(p)).font(.system(size: 11)).foregroundStyle(W.dim)
                    // A fresh window waiting is the one moment there's something to do, so offer it.
                    if W.isReady(p, at: e.date) && (p.blockedUntil.map { $0 <= e.date } ?? true) {
                        StartNowButton(snap: e.snap, date: e.date, compact: true).padding(.top, 2)
                    } else {
                        Segments(health: W.health(p, at: e.date), color: W.color("claude")).padding(.top, 2)
                    }
                } else {
                    Text("Open Reset").font(.system(size: 13)).foregroundStyle(W.dim)
                }
            }
        }
        .containerBackground(for: .widget) {
            ZStack { W.bg; RadialGradient(colors: [W.color("claude").opacity(0.35), .clear], center: .topTrailing, startRadius: 0, endRadius: 140) }
        }
    }
    private func subtitle(_ p: WidgetSnapshot.Provider) -> String {
        if W.isReady(p, at: e.date) { return "fresh window waiting" + (p.estimate != nil ? " · est." : "") }
        var s = p.resetsAt.map { "resets " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
        if let u = p.used { s += " · \(Int((100 - u).rounded()))% left" }
        // Too small for the reason; "est." is enough to not read as exact, and the menu says why.
        if p.estimate != nil { s += " · est." }
        return s
    }
}

func money(_ v: Double) -> String { v >= 1000 ? "$" + String(Int(v.rounded())) : String(format: "$%.0f", v) }

// MARK: Large: Claude week

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.week", provider: Provider()) { e in WeekLarge(e: e) }
            .configurationDisplayName("Claude week")
            .description("Countdown, burn bar, your windows this week and what they were worth.")
            .supportedFamilies([.systemLarge])
    }
}

struct WeekLarge: View {
    let e: Entry
    var body: some View {
        let p = e.snap?.claude
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude").font(.system(size: 13, weight: .medium))
                    // The large widget has room for the whole reason.
                    Text((p?.resetsAt.map { "resets " + $0.formatted(date: .omitted, time: .shortened) } ?? " ")
                         + (p?.estimate.map { " · " + $0 } ?? ""))
                        .font(.system(size: 11)).foregroundStyle(W.dim).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer()
                if let p, let img = W.mascot("claude", p, at: e.date) {
                    img.resizable().aspectRatio(contentMode: .fit).frame(width: 74, height: 74).offset(y: -6)
                }
            }
            if let p {
                Countdown(p: p, date: e.date, size: 52).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                Segments(health: W.health(p, at: e.date), color: W.color("claude"), count: 20)
            }
            Text("This week").font(.system(size: 11)).foregroundStyle(W.dim).padding(.top, 4)
            Barcode(windows: e.snap?.windows ?? [], date: e.date).frame(height: 120)
            HStack {
                if let m = e.snap?.weekMultiple { stat(String(format: "%.1f×", m), "value") }
                else { stat("\(weekWindows)", "windows") }
                Spacer()
                stat(money(e.snap?.weekCost ?? 0), "this week")
                Spacer()
                stat(String(format: "%.0f%%", (e.snap?.cacheHit ?? 0) * 100), "cache hit")
            }
        }
        .containerBackground(for: .widget) {
            ZStack { W.bg; RadialGradient(colors: [W.color("claude").opacity(0.3), .clear], center: .top, startRadius: 0, endRadius: 220) }
        }
    }
    private var weekWindows: Int {
        let start = Calendar.current.startOfDay(for: e.date.addingTimeInterval(-6 * 86400))
        return (e.snap?.windows ?? []).filter { $0.start >= start }.count
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 20, weight: .light).monospacedDigit())
            Text(l).font(.system(size: 10)).foregroundStyle(W.dim)
        }
    }
}

struct Barcode: View {
    let windows: [WidgetSnapshot.Window]
    let date: Date
    var days = 5
    var body: some View {
        Canvas { ctx, size in
            let cal = Calendar.current
            let today = cal.startOfDay(for: date)
            let rowH = (size.height - CGFloat(days - 1) * 6) / CGFloat(days)
            let amber = W.color("claude")
            for i in 0..<days {
                let day = cal.date(byAdding: .day, value: i - (days - 1), to: today)!
                let y = CGFloat(i) * (rowH + 6)
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: y, width: size.width, height: rowH), cornerRadius: 4), with: .color(.white.opacity(0.05)))
                let end = day.addingTimeInterval(86400)
                for w in windows where w.end > day && w.start < end {
                    let x0 = size.width * CGFloat(max(w.start, day).timeIntervalSince(day) / 86400)
                    let x1 = size.width * CGFloat(min(w.end, end).timeIntervalSince(day) / 86400)
                    let r = CGRect(x: x0 + 1, y: y + 1, width: max(2, x1 - x0 - 2), height: rowH - 2)
                    if w.autoStart { ctx.stroke(Path(roundedRect: r, cornerRadius: 4), with: .color(amber), lineWidth: 1.2) }
                    else { ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(amber.opacity(0.85))) }
                    if w.hitLimit, w.end <= end {
                        ctx.fill(Path(roundedRect: CGRect(x: r.maxX - 4, y: r.minY, width: 4, height: r.height), cornerRadius: 1), with: .color(.red))
                    }
                }
                if cal.isDate(day, inSameDayAs: date) {
                    let x = size.width * CGFloat(date.timeIntervalSince(day) / 86400)
                    var path = Path(); path.move(to: CGPoint(x: x, y: y - 2)); path.addLine(to: CGPoint(x: x, y: y + rowH + 2))
                    ctx.stroke(path, with: .color(.white), lineWidth: 1.2)
                }
            }
        }
    }
}

extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        let now = Date()
        return WidgetSnapshot(updated: now, providers: [
            .init(id: "claude", name: "Claude", resetsAt: now.addingTimeInterval(9600), ready: false, available: true, used: 62),
            .init(id: "gemini", name: "Gemini CLI", resetsAt: now.addingTimeInterval(40000), ready: false, available: true, used: nil),
            .init(id: "antigravity", name: "Antigravity", resetsAt: nil, ready: true, available: true, used: 0),
        ], windows: [], weekCost: 412, weekMultiple: nil, cacheHit: 0.98)
    }
}
