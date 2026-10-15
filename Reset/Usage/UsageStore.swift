import AppKit
import SwiftUI
import Foundation
import Observation

enum UsageRange: String, CaseIterable, Identifiable {
    case today = "Today", week = "7 days", month = "30 days", all = "All"
    var id: String { rawValue }
    func start(now: Date) -> Date {
        switch self {
        case .today: return Calendar.current.startOfDay(for: now)
        case .week: return now.addingTimeInterval(-7 * 86400)
        case .month: return now.addingTimeInterval(-30 * 86400)
        case .all: return now.addingTimeInterval(-UsageStore.historyDays * 86400)
        }
    }
    /// For the value multiple: how many days of plan price this range covers.
    func days(now: Date) -> Double { max(1 / 24, now.timeIntervalSince(start(now: now)) / 86400) }
}

struct SessionSummary: Identifiable {
    var id: String
    var title: String
    var project: String
    var projectName: String { ProjectNames.shared.name(for: project) }
    var start: Date
    var end: Date
    var cost: Double
    var input = 0, cacheWrite = 0, cacheRead = 0, output = 0
    var tools = 0, mcpCalls = 0, webSearches = 0
    var apiMillis: Int?
    var modelCost: [String: Double] = [:]
    /// Where the cost went: main thread, subagents, and each MCP server's calls.
    var mainCost = 0.0, subagentCost = 0.0
    var mcpCost: [String: Double] = [:]
    var subagentCalls = 0

    var topModel: String { modelCost.max { $0.value < $1.value }?.key ?? "" }
    var cacheHit: Double {
        let denom = Double(input + cacheWrite + cacheRead)
        return denom > 0 ? Double(cacheRead) / denom : 0
    }
}

struct UsageWindow: Identifiable {
    var id: Date { start }
    var start: Date
    var end: Date
    var autoStart: Bool
    var hitLimit: Bool
}

@Observable
final class UsageStore {
    static let historyDays: Double = 35

    private(set) var calls: [Call] = []
    private(set) var titles: [String: String] = [:]
    private(set) var limitHits: [Date] = []
    private(set) var apiMillis: [String: Int] = [:]
    /// Whether Claude Code's recent logs still read cleanly; Settings warns when they don't.
    private(set) var format = ClaudeUsageScanner.FormatReport()
    private(set) var loading = false
    /// Files parsed so far in the current scan, for the first-launch progress message.
    private(set) var filesRead = 0
    private(set) var lastScan: Date?
    var range: UsageRange = UsageRange(rawValue: UserDefaults.standard.string(forKey: "usageRange") ?? "") ?? .month {
        didSet { UserDefaults.standard.set(range.rawValue, forKey: "usageRange") }
    }
    var selectedSession: String?
    /// Set from the menu's Share button; the dashboard opens the share sheet when it sees it.
    var shareRequested = false
    var planMonthlyUSD: Double { didSet { UserDefaults.standard.set(planMonthlyUSD, forKey: "planMonthlyUSD") } }

    private let scanner = ClaudeUsageScanner()
    private let queue = DispatchQueue(label: "reset.usage", qos: .utility)
    private var timer: Timer?

    init() {
        planMonthlyUSD = UserDefaults.standard.double(forKey: "planMonthlyUSD")
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        if Demo.isOn {
            let d = Demo.calls()
            calls = d.calls; titles = d.titles; limitHits = d.limitHits; apiMillis = d.api
            lastScan = Date()
            if let path = UserDefaults.standard.string(forKey: "renderShareCard") {
                DispatchQueue.main.async {
                    if let img = ShareSheet.render(ShareSheet.model(self, mascot: true)), let t = img.tiffRepresentation,
                       let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: path))
                    }
                }
            }
            // Test hook: `-renderDashboard /path.png` writes the whole dashboard once.
            if let path = UserDefaults.standard.string(forKey: "renderDashboard") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    let v = DashboardView(store: Store.shared, usage: self, flat: true).frame(width: 1240)
                    let r = ImageRenderer(content: v); r.scale = 2
                    if let img = r.nsImage, let t = img.tiffRepresentation,
                       let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: path))
                    }
                }
            }
            return
        }
        guard !loading else { return }
        loading = true
        filesRead = 0
        scanner.progress = { [weak self] n in DispatchQueue.main.async { self?.filesRead = n } }
        let since = Date().addingTimeInterval(-Self.historyDays * 86400)
        queue.async { [weak self] in
            guard let self else { return }
            let r = self.scanner.scan(since: since)
            DispatchQueue.main.async {
                self.calls = r.calls
                self.titles = r.titles
                self.limitHits = r.limitHits
                self.apiMillis = r.apiMillis
                self.format = r.format
                self.loading = false
                self.lastScan = Date()
                // Test hook: `--args -renderShareCard /path/card.png` writes the current card once.
                if let path = UserDefaults.standard.string(forKey: "renderShareCard"),
                   let img = ShareSheet.render(ShareSheet.model(self, mascot: true)),
                   let tiff = img.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
            }
        }
    }

    // MARK: Aggregates for the selected range

    var inRange: [Call] {
        let s = range.start(now: Date())
        return calls.filter { $0.time >= s }
    }

    var totalCost: Double { inRange.reduce(0) { $0 + $1.cost } }

    /// The plan price used for value maths; demo mode uses its own so screenshots never show the real one.
    var effectivePlan: Double { Demo.isOn ? 100 : planMonthlyUSD }
    var planCostForRange: Double { effectivePlan * range.days(now: Date()) / 30 }

    var valueMultiple: Double? {
        let plan = planCostForRange
        return plan > 0 ? totalCost / plan : nil
    }

    /// What reading the same tokens as fresh input would have cost, minus what the cache reads cost.
    var cacheSaved: Double {
        inRange.reduce(0) { acc, c in
            guard let p = Pricing.claude(c.model) else { return acc }
            return acc + Double(c.cacheRead) * (p.input - p.cacheRead) / 1_000_000
        }
    }

    struct Mix { var cacheRead = 0, cacheWrite = 0, output = 0, input = 0
        var total: Int { cacheRead + cacheWrite + output + input } }

    var tokenMix: Mix {
        inRange.reduce(into: Mix()) { m, c in
            m.cacheRead += c.cacheRead; m.cacheWrite += c.cw5 + c.cw1h; m.output += c.output; m.input += c.input + c.advisorTokens
        }
    }

    /// Output tokens by weekday (Mon = 0) and hour, over the full history.
    var heatmap: [[Double]] {
        var g = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        let cal = Calendar.current
        for c in calls {
            let wd = (cal.component(.weekday, from: c.time) + 5) % 7
            g[wd][cal.component(.hour, from: c.time)] += Double(c.output)
        }
        return g
    }

    var busiestHour: Int? {
        var byHour = Array(repeating: 0.0, count: 24)
        for row in heatmap { for h in 0..<24 { byHour[h] += row[h] } }
        guard let m = byHour.max(), m > 0 else { return nil }
        return byHour.firstIndex(of: m)
    }

    var sessions: [SessionSummary] {
        var map: [String: SessionSummary] = [:]
        for c in inRange {
            var s = map[c.session] ?? SessionSummary(id: c.session, title: titles[c.session] ?? Self.fallbackTitle(c.project),
                                                       project: c.project, start: c.time, end: c.time, cost: 0)
            s.start = min(s.start, c.time); s.end = max(s.end, c.time)
            s.cost += c.cost
            s.input += c.input; s.cacheWrite += c.cw5 + c.cw1h; s.cacheRead += c.cacheRead; s.output += c.output
            s.tools += c.tools; s.mcpCalls += c.mcpCalls; s.webSearches += c.webSearches
            s.modelCost[c.model, default: 0] += c.cost
            if let server = c.mcpAttribution { s.mcpCost[server, default: 0] += c.cost }
            else if c.sidechain { s.subagentCost += c.cost; s.subagentCalls += 1 }
            else { s.mainCost += c.cost }
            map[c.session] = s
        }
        for k in map.keys { map[k]?.apiMillis = apiMillis[k] }
        return map.values.sorted { $0.cost > $1.cost }
    }

    static func fallbackTitle(_ project: String) -> String { ProjectNames.shared.name(for: project) }

    struct ProjectSummary: Identifiable {
        var id: String { root }
        var root: String
        var cost: Double
        var sessions: Int
        var last: Date
    }

    /// Projects in the selected range, folded to their root folder, most expensive first.
    var projects: [ProjectSummary] {
        var map: [String: (Double, Set<String>, Date)] = [:]
        for c in inRange {
            let r = ProjectNames.root(of: c.project)
            var e = map[r] ?? (0, [], c.time)
            e.0 += c.cost; e.1.insert(c.session); e.2 = max(e.2, c.time)
            map[r] = e
        }
        return map.map { ProjectSummary(root: $0.key, cost: $0.value.0, sessions: $0.value.1.count, last: $0.value.2) }
            .sorted { $0.cost > $1.cost }
    }

    /// 5-hour windows over the last `days`, rebuilt from activity the same way the reset estimate is.
    func windows(days: Int = 7) -> [UsageWindow] {
        let since = Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(days - 1) * 86400))
        var out: [UsageWindow] = []
        for c in calls where c.time >= since.addingTimeInterval(-5 * 3600) {
            if let last = out.last, c.time < last.end { continue }
            let start = ClaudeSource.floorTo10(c.time)
            out.append(UsageWindow(start: start, end: start.addingTimeInterval(5 * 3600), autoStart: c.autoStart, hitLimit: false))
        }
        for h in limitHits {
            if let i = out.firstIndex(where: { $0.start <= h && h < $0.end }) { out[i].hitLimit = true }
        }
        return out.filter { $0.end > since }
    }
}
