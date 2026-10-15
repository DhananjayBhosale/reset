import AppKit
import SwiftUI
import Foundation
import Observation
import ServiceManagement
import WidgetKit

/// Per-provider switches, saved in UserDefaults.
struct ProviderPrefs: Codable, Equatable {
    var enabled = true
    var alert = true
    var autoStart = false
}

@Observable
final class Store {
    private(set) var statuses: [WindowStatus] = []
    private(set) var lastRefresh = Date.distantPast
    private(set) var log: [String] = []
    var now = Date()

    // Saved settings
    var prefs: [String: ProviderPrefs] { didSet { save(prefs, "prefs") } }
    var custom: [CustomProvider] { didSet { save(custom, "custom"); refresh() } }
    var claudeExtraStarts: [Date] { didSet { save(claudeExtraStarts, "claudeExtraStarts"); refresh() } }
    var leadMinutes: Int { didSet { UserDefaults.standard.set(leadMinutes, forKey: "leadMinutes"); syncAlerts() } }
    var phoneEnabled: Bool { didSet { UserDefaults.standard.set(phoneEnabled, forKey: "phoneEnabled"); syncAlerts() } }
    var ntfyServer: String { didSet { UserDefaults.standard.set(ntfyServer, forKey: "ntfyServer"); syncAlerts() } }
    var ntfyTopic: String { didSet { UserDefaults.standard.set(ntfyTopic, forKey: "ntfyTopic"); syncAlerts() } }
    var commands: [String: String] { didSet { save(commands, "commands") } }
    var liveClaudeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(liveClaudeEnabled, forKey: "liveClaude")
            if liveClaudeEnabled { note("Live Claude usage on") } else { liveClaude.reset() }
            refresh()
        }
    }
    let liveClaude = LiveClaude()
    let forecast = Forecast()
    var look: Look = Look(rawValue: UserDefaults.standard.string(forKey: "look") ?? "") ?? .glow {
        didSet { UserDefaults.standard.set(look.rawValue, forKey: "look"); lastWidgetData = nil; writeWidgetSnapshot() }
    }

    /// What a look card needs for one provider, with the mascot in its current mood.
    func cardData(for s: WindowStatus) -> CardData {
        let window: TimeInterval = s.id == "gemini" ? 86400 : 5 * 3600
        return CardData(id: s.id, name: s.name, color: Theme.color(for: s.id), windowStart: s.resetsAt?.addingTimeInterval(-window),
                        resetsAt: s.resetsAt, ready: s.state == .ready, blockedUntil: s.blockedUntil, used: s.usedPercent,
                        mascot: MascotArt.image(s.id, Mood.of(s, justReset: false)).map { Image(nsImage: $0) }, windowLength: window)
    }

    let alerts = Alerts()
    let kicker = Kicker()
    let mascots = MascotController()
    let usage = UsageStore()
    private var tick: Timer?
    private var lastScan = Date.distantPast
    private var scanning = false
    private var rescanQueued = false
    private let scanQueue = DispatchQueue(label: "reset.scan", qos: .utility)

    /// Auto-start bookkeeping. A kick is only due after Reset itself watched a window run out while
    /// auto-start was on, so switching the toggle on never fires a command straight away, and a source
    /// that stays READY after a kick does not trigger another one.
    private var lastSeenReset: [String: Date] = (UserDefaults.standard.dictionary(forKey: "lastSeenReset") as? [String: Date]) ?? [:] {
        didSet { UserDefaults.standard.set(lastSeenReset, forKey: "lastSeenReset") }
    }
    private var kickDue: [String: (reset: Date, attempts: Int)] = [:]
    private var armedAt: [String: Date] = [:]

    init() {
        let d = UserDefaults.standard
        prefs = Self.load("prefs") ?? [:]
        custom = Self.load("custom") ?? []
        claudeExtraStarts = Self.load("claudeExtraStarts") ?? []
        leadMinutes = d.object(forKey: "leadMinutes") as? Int ?? 0
        phoneEnabled = d.bool(forKey: "phoneEnabled")
        ntfyServer = d.string(forKey: "ntfyServer") ?? "https://ntfy.sh"
        ntfyTopic = d.string(forKey: "ntfyTopic") ?? ""
        commands = Self.load("commands") ?? Kicker.defaultCommands()
        liveClaudeEnabled = d.bool(forKey: "liveClaude")
        if prefs["antigravity"] == nil {
            let has = FileManager.default.fileExists(atPath: "/Applications/Antigravity.app")
            prefs["antigravity"] = ProviderPrefs(enabled: has, alert: has)
        }
        if prefs["gemini"] == nil {
            let hasGemini = FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.gemini")
            prefs["gemini"] = ProviderPrefs(enabled: hasGemini, alert: false)
        }
    }

    func start() {
        alerts.requestPermission()
        mascots.attach(self)
        usage.start()
        refresh()
        // A 1 s tick keeps the countdowns live; disk is rescanned every 60 s or on demand.
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.onTick() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.note("Mac woke up, rescanning")
            self?.refresh()
            // Wi-Fi is often still reconnecting right after wake; rescan again so phone pushes retry soon.
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self?.refresh() }
        }
    }

    private func onTick() {
        now = Date()
        let crossedReset = statuses.contains { s in s.resetsAt.map { $0 <= now } ?? false }
        if crossedReset || now.timeIntervalSince(lastScan) >= 60 { refresh() }
        if now.timeIntervalSince(lastStatusLine) >= 30 { writeStatusLine() }
        runAutoStarts()
    }

    func prefs(for id: String) -> ProviderPrefs { prefs[id] ?? ProviderPrefs() }

    func setPrefs(_ id: String, _ update: (inout ProviderPrefs) -> Void) {
        var p = prefs(for: id)
        let wasAuto = p.autoStart
        update(&p)
        prefs[id] = p
        mascots.sync()
        if p.autoStart && !wasAuto { armedAt[id] = Date(); kickDue[id] = nil }
        syncAlerts()
    }

    var visible: [WindowStatus] { statuses.filter { prefs(for: $0.id).enabled } }

    /// The window that resets soonest, for the menu bar label.
    /// Providers you asked to be alerted about drive the menu bar; the rest only show in the menu.
    private var barCandidates: [WindowStatus] {
        let alerted = visible.filter { prefs(for: $0.id).alert }
        return alerted.isEmpty ? visible : alerted
    }

    var soonest: WindowStatus? {
        barCandidates.filter { $0.resetsAt != nil }.min { $0.resetsAt! < $1.resetsAt! }
    }

    /// A tracked provider with a fresh window waiting, shown in the bar ahead of any countdown.
    var readyForBar: WindowStatus? {
        barCandidates.first { $0.state == .ready && $0.blockedUntil == nil }
    }

    func refresh() {
        lastScan = Date()
        if Demo.isOn {
            statuses = [Demo.claude()]
            lastRefresh = Date()
            now = Date()
            mascots.sync()
            return
        }
        // One scan at a time; a request during a scan runs once more afterwards with fresh inputs.
        guard !scanning else { rescanQueued = true; return }
        scanning = true
        let extras = claudeExtraStarts
        let custom = self.custom
        scanQueue.async { [weak self] in
            let t = Date()
            var list: [WindowStatus] = [
                ClaudeSource(extraStarts: extras).read(now: t),
                CodexSource().read(now: t),
                GeminiSource().read(now: t),
                AntigravitySource().read(now: t),
            ]
            list += custom.map { $0.status(now: t) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                var list = list
                if self.liveClaudeEnabled, let i = list.firstIndex(where: { $0.id == "claude" }) {
                    self.liveClaude.apply(to: &list[i], now: Date())
                    self.liveClaude.poll { [weak self] in self?.refresh() }
                    if !list[i].isEstimate, let u = list[i].usedPercent {
                        self.forecast.record(used: u, resetsAt: list[i].resetsAt)
                        self.warnIfRunningOut(list[i])
                    }
                }
                self.statuses = list
                self.lastRefresh = t
                self.now = Date()
                self.trackResets()
                self.writeWidgetSnapshot()
                self.writeStatusLine()
                self.mascots.sync()
                self.syncAlerts()
                self.runAutoStarts()
                if self.rescanQueued { self.rescanQueued = false; self.refresh() }
                // Test hook: `--args -renderMenu /path/menu.png` renders the menu panel once.
                if let path = UserDefaults.standard.string(forKey: "renderMenu"), !self.renderedMenu {
                    self.renderedMenu = true
                    let r = ImageRenderer(content: MenuView(store: self)); r.scale = 2
                    if let img = r.nsImage, let t = img.tiffRepresentation,
                       let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: path))
                    }
                }
            }
        }
    }

    func syncAlerts() {
        let targets = visible.filter { prefs(for: $0.id).alert }
        alerts.sync(targets, leadMinutes: leadMinutes)
        alerts.syncPhone(targets, server: ntfyServer, topic: ntfyTopic, enabled: phoneEnabled, log: note)
    }

    /// Remembers each provider's reset time while a window runs, and marks a kick as due once that time
    /// passes with auto-start on. A new window (from you or from a kick) clears it.
    private func trackResets() {
        let t = Date()
        for s in statuses {
            if let r = s.resetsAt {
                lastSeenReset[s.id] = r
                kickDue[s.id] = nil
            } else if s.state == .ready, let r = lastSeenReset[s.id], r <= t {
                lastSeenReset[s.id] = nil
                let p = prefs(for: s.id)
                if s.canAutoStart, p.enabled, p.autoStart, r > (armedAt[s.id] ?? .distantPast) {
                    kickDue[s.id] = (r, 0)
                }
            }
        }
    }

    private func runAutoStarts() {
        let t = Date()
        for (id, due) in kickDue {
            guard let s = statuses.first(where: { $0.id == id }), prefs(for: id).autoStart,
                  let cmd = commands[id], !cmd.isEmpty else { kickDue[id] = nil; continue }
            if let b = s.blockedUntil, b > t {
                note("\(s.name): \(s.secondary?.label ?? "longer") limit still exhausted, not auto-starting")
                kickDue[id] = nil
                continue
            }
            // Two minutes of slack past the reset, so a slightly early estimate does not burn a kick.
            guard s.state == .ready, t >= due.reset.addingTimeInterval(120) else { continue }
            guard due.attempts < 4 else { kickDue[id] = nil; note("\(s.name): auto-start gave up after 4 tries"); continue }
            kicker.kick(id, name: s.name, command: cmd, log: note) { [weak self] ok in
                guard let self else { return }
                if ok { self.kickDue[id] = nil }
                else if var d = self.kickDue[id] { d.attempts += 1; self.kickDue[id] = d }
                self.refresh()
            }
        }
    }

    // MARK: Claude Code status line

    private var lastStatusLine = Date.distantPast

    /// One line for Claude Code's status bar, read with `cat` by a statusLine command.
    func writeStatusLine() {
        guard !Demo.isOn else { return }
        guard let c = statuses.first(where: { $0.id == "claude" }) else { return }
        lastStatusLine = Date()
        var parts: [String] = []
        switch c.state {
        case .ready: parts.append("Claude ready")
        case .unavailable: parts.append("Claude --")
        case .active(let end):
            var s = "Claude"
            if let u = c.usedPercent { s += " \(Int((100 - u).rounded()))% left" }
            s += " · \(Fmt.countdown(end.timeIntervalSince(Date()))) to \(Fmt.clock.string(from: end))"
            parts.append(s)
        }
        if let b = c.blockedUntil, b > Date() { parts.append("weekly limit until \(Fmt.when(b))") }
        if let out = forecast.runsOutAt { parts.append("runs out ~\(Fmt.clock.string(from: out))") }
        let today = usage.calls.filter { Calendar.current.isDateInToday($0.time) }.reduce(0) { $0 + $1.cost }
        if today > 0 { parts.append(String(format: "$%.0f today", today)) }
        let line = "◷ " + parts.joined(separator: " · ")
        let url = WidgetSnapshot.url.deletingLastPathComponent().appendingPathComponent("statusline.txt")
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Forecast

    /// Mac notification plus an immediate phone push, once per window, when the limit is projected to arrive first.
    private func warnIfRunningOut(_ s: WindowStatus) {
        guard forecast.shouldWarn(), let out = forecast.runsOutAt, let reset = s.resetsAt else { return }
        let title = "\(s.name) will run out before it resets"
        let body = "At this pace you hit the limit around \(Fmt.clock.string(from: out)), \(Fmt.countdown(reset.timeIntervalSince(out))) before the \(Fmt.clock.string(from: reset)) reset."
        alerts.notifyNow(title: title, body: body)
        if phoneEnabled { alerts.pushNow(title: title, body: body, server: ntfyServer, topic: ntfyTopic, log: note) }
        note("Forecast: limit around \(Fmt.clock.string(from: out))")
    }

    // MARK: Widgets

    var lastWidgetData: Data?
    private var renderedMenu = false

    /// Writes what the desktop widgets show and asks WidgetKit to redraw, only when something changed.
    func writeWidgetSnapshot() {
        guard !Demo.isOn else { return }
        let week = usage.calls.filter { $0.time >= Date().addingTimeInterval(-7 * 86400) }
        let weekCost = week.reduce(0) { $0 + $1.cost }
        let cr = week.reduce(0) { $0 + $1.cacheRead }, rest = week.reduce(0) { $0 + $1.input + $1.cw5 + $1.cw1h }
        let plan = usage.planMonthlyUSD * 7 / 30
        let providers = visible.filter { MascotArt.providers.contains($0.id) }.map { s -> WidgetSnapshot.Provider in
            var available = true
            if case .unavailable = s.state { available = false }
            return .init(id: s.id, name: s.name, resetsAt: s.resetsAt, ready: s.state == .ready, available: available,
                         used: s.usedPercent, blockedUntil: s.blockedUntil)
        }
        let windows = usage.windows(days: 5).map { WidgetSnapshot.Window(start: $0.start, end: $0.end, autoStart: $0.autoStart, hitLimit: $0.hitLimit) }
        var snap = WidgetSnapshot(updated: .distantPast, look: look, providers: providers, windows: windows, weekCost: weekCost,
                                  weekMultiple: plan > 0 ? weekCost / plan : nil,
                                  cacheHit: cr + rest > 0 ? Double(cr) / Double(cr + rest) : 0)
        let month = usage.calls.filter { $0.time >= Date().addingTimeInterval(-30 * 86400) }
        let monthCost = month.reduce(0) { $0 + $1.cost }
        snap.monthCost = monthCost
        snap.monthMultiple = usage.planMonthlyUSD > 0 ? monthCost / usage.planMonthlyUSD : nil
        snap.monthCacheSaved = month.reduce(0) { acc, c in
            guard let p = Pricing.claude(c.model) else { return acc }
            return acc + Double(c.cacheRead) * (p.input - p.cacheRead) / 1_000_000
        }
        let mix = month.reduce(into: [0, 0, 0, 0]) { m, c in m[0] += c.cacheRead; m[1] += c.cw5 + c.cw1h; m[2] += c.output; m[3] += c.input + c.advisorTokens }
        snap.monthMix = mix
        snap.monthTokens = mix.reduce(0, +)
        let grid = usage.heatmap
        let gmax = grid.flatMap { $0 }.max() ?? 0
        snap.heatmap = gmax > 0 ? grid.map { $0.map { ($0 / gmax * 100).rounded() / 100 } } : grid
        var hours = Array(repeating: 0.0, count: 24)
        let cal = Calendar.current
        for c in usage.calls where cal.isDateInToday(c.time) { hours[cal.component(.hour, from: c.time)] += Double(c.output) }
        let hmax = hours.max() ?? 0
        snap.today = hours.map { hmax > 0 ? ($0 / hmax * 100).rounded() / 100 : 0 }

        // Daily and hourly spend, projects, calendar.
        let today0 = cal.startOfDay(for: Date())
        var daily = Array(repeating: 0.0, count: 14)
        var hourT = Array(repeating: 0.0, count: 24), hourY = Array(repeating: 0.0, count: 24)
        var proj: [String: Double] = [:]
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let daysInMonth = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        var mdays = Array(repeating: 0.0, count: daysInMonth)
        for c in usage.calls {
            let d = cal.dateComponents([.day], from: cal.startOfDay(for: c.time), to: today0).day ?? 99
            if d >= 0 && d < 14 { daily[13 - d] += c.cost }
            if d == 0 { hourT[cal.component(.hour, from: c.time)] += c.cost }
            if d == 1 { hourY[cal.component(.hour, from: c.time)] += c.cost }
            if c.time >= Date().addingTimeInterval(-30 * 86400) {
                let name = ProjectNames.shared.name(for: c.project)
                proj[name, default: 0] += c.cost
            }
            if c.time >= monthStart { mdays[cal.component(.day, from: c.time) - 1] += c.cost }
        }
        func cumulative(_ a: [Double]) -> [Double] { var s = 0.0; return a.map { s += $0; return (s * 100).rounded() / 100 } }
        snap.dailyCost = daily.map { ($0 * 100).rounded() / 100 }
        snap.todayCumulative = cumulative(hourT)
        snap.yesterdayCumulative = cumulative(hourY)
        snap.projects = proj.sorted { $0.value > $1.value }.prefix(6).map { .init(name: $0.key, cost: ($0.value * 100).rounded() / 100) }
        snap.monthDays = mdays.map { ($0 * 100).rounded() / 100 }
        snap.claudeRunsOutAt = forecast.runsOutAt
        snap.limitDays = Array(Set(usage.limitHits.filter { $0 >= monthStart }.map { cal.component(.day, from: $0) })).sorted()

        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        let key = try? enc.encode(snap)
        guard key != lastWidgetData else { return }
        lastWidgetData = key
        snap.updated = Date()
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: User actions

    /// "I just used Claude on the web or desktop chat": opens a window now if none is running.
    func markClaudeUsedElsewhere() {
        claudeExtraStarts = (claudeExtraStarts + [Date()]).filter { $0 > Date().addingTimeInterval(-36000) }
    }

    func startCustom(_ id: String) {
        guard let i = custom.firstIndex(where: { "custom-" + $0.id == id }) else { return }
        custom[i].startedAt = Date()
    }

    func clearCustom(_ id: String) {
        guard let i = custom.firstIndex(where: { "custom-" + $0.id == id }) else { return }
        custom[i].startedAt = nil
    }

    func sendTestPush() {
        alerts.sendTest(server: ntfyServer, topic: ntfyTopic, log: note)
    }

    func kickNow(_ id: String) {
        guard let cmd = commands[id], let s = statuses.first(where: { $0.id == id }) else { return }
        kicker.kick(id, name: s.name, command: cmd, force: true, log: note) { [weak self] _ in self?.refresh() }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { note("Launch at login failed: \(error.localizedDescription)") }
        }
    }

    func note(_ s: String) {
        let line = "\(Fmt.clock.string(from: Date()))  \(s)"
        DispatchQueue.main.async { self.log = Array(([line] + self.log).prefix(40)) }
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ v: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
