import Foundation

/// Opt-in exact Claude usage: reads Claude Code's own sign-in from the Keychain and asks Anthropic's usage
/// endpoint for the current 5-hour and weekly windows. Only usage numbers are fetched, the token is only
/// ever sent to api.anthropic.com, and Reset never refreshes or rewrites it (that would sign Claude Code out).
final class LiveClaude {
    struct Window: Codable, Equatable { var percent: Double; var resetsAt: Date? }
    struct Snapshot: Codable, Equatable { var fiveHour: Window?; var sevenDay: Window?; var fetchedAt: Date }

    /// When Reset last asked, until when Anthropic told it to wait, and the last good reading. Saved to
    /// live-schedule.json and re-read before every fetch, so a restart (or a second copy of the app) respects a
    /// "slow down" instead of asking again straight away, and shows the last reading instead of an estimate.
    struct Schedule: Codable, Equatable {
        var lastAttempt: Date = .distantPast
        var backoffUntil: Date = .distantPast
        var lastGood: Snapshot?
        /// Every "slow down" (HTTP 429) received, newest last, to learn where Anthropic's undocumented limit sits.
        /// Optional so schedules saved before it existed still load.
        var limits: [LimitHit]? = nil
    }

    /// One "slow down": when, and how long Anthropic asked Reset to wait (its Retry-After header), if it said.
    struct LimitHit: Codable, Equatable {
        var at: Date
        var retryAfter: Double?
    }

    /// Only the most recent hits are kept; enough to see a pattern over a few days.
    static let keptLimitHits = 50

    /// The saved "slow down" log, for the self-test.
    var limitHits: [LimitHit] { Self.loadSchedule(scheduleURL)?.limits ?? [] }

    /// A reading older than this says nothing about the current window; matches what `apply` accepts.
    static let freshFor: TimeInterval = 15 * 60

    static var scheduleURL: URL { WidgetSnapshot.url.deletingLastPathComponent().appendingPathComponent("live-schedule.json") }

    static func loadSchedule(_ url: URL?) -> Schedule? {
        guard let url, let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(Schedule.self, from: d)
    }

    static func saveSchedule(_ s: Schedule, to url: URL?) {
        guard let url else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        guard let d = try? enc.encode(s) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: url, options: .atomic)
    }

    /// Whether a fetch is due: the interval has passed since the last attempt, and any back-off is over.
    static func shouldFetch(now: Date, lastAttempt: Date, backoffUntil: Date, interval: TimeInterval) -> Bool {
        now.timeIntervalSince(lastAttempt) >= interval && now >= backoffUntil
    }

    enum State: Equatable {
        case off, loading
        case ok(Date)
        case problem(String)
    }

    private(set) var snapshot: Snapshot?
    private(set) var state: State = .off
    /// True when the failure is about Claude Code's sign-in, which the user has to fix (not a network blip).
    private(set) var needsSignIn = false
    private var lastAttempt = Date.distantPast
    private var backoffUntil = Date.distantPast
    private let lock = NSLock()
    private let scheduleURL: URL?

    /// With no `scheduleURL` nothing is read or written (tests).
    init(scheduleURL: URL? = nil, now: Date = Date()) {
        self.scheduleURL = scheduleURL
        guard let saved = Self.loadSchedule(scheduleURL) else { return }
        lastAttempt = saved.lastAttempt
        backoffUntil = saved.backoffUntil
        if let good = saved.lastGood, now.timeIntervalSince(good.fetchedAt) < Self.freshFor {
            snapshot = good
            state = .ok(good.fetchedAt)
        }
    }

    /// Saves the schedule, keeping whatever is latest on disk (another copy of the app may have asked since).
    private func persist(_ update: (inout Schedule) -> Void) {
        guard scheduleURL != nil else { return }
        var s = Self.loadSchedule(scheduleURL) ?? Schedule()
        update(&s)
        Self.saveSchedule(s, to: scheduleURL)
    }

    /// How often to ask: every 2 minutes while Claude Code is in use, when the numbers move and you're watching
    /// them, and every 5 minutes otherwise. Once a minute drew Anthropic's first "slow down" within 40 minutes
    /// (alongside a lot of restarts), and the endpoint isn't a public API with a published limit, so 2 minutes it
    /// is until the 429 log says more is safe. Just under 120 s, because the app's refresh runs every 60 s and a
    /// strict 120 would sometimes miss a tick and wait three.
    static let activeInterval: TimeInterval = 115, idleInterval: TimeInterval = 300
    static let activeWindow: TimeInterval = 5 * 60

    static func interval(lastActivity: Date?, now: Date = Date()) -> TimeInterval {
        guard let a = lastActivity, now.timeIntervalSince(a) < activeWindow else { return idleInterval }
        return activeInterval
    }

    /// Fetch if the last one is older than `interval`. Calls `done` on the main queue when something changed.
    func poll(interval: TimeInterval = 180, done: @escaping () -> Void) {
        lock.lock()
        let now = Date()
        // Whatever another copy (or this one before a restart) recorded counts too.
        if let disk = Self.loadSchedule(scheduleURL) {
            lastAttempt = max(lastAttempt, disk.lastAttempt)
            backoffUntil = max(backoffUntil, disk.backoffUntil)
        }
        guard Self.shouldFetch(now: now, lastAttempt: lastAttempt, backoffUntil: backoffUntil, interval: interval) else { lock.unlock(); return }
        lastAttempt = now
        lock.unlock()
        persist { $0.lastAttempt = now }
        if snapshot == nil { state = .loading }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            // Test hook: `-simulateSignedOut YES` behaves as if Claude Code's sign-in expired.
            if UserDefaults.standard.bool(forKey: "simulateSignedOut") {
                self.finish(.problem("Claude Code's sign-in has expired. Open Claude Code once and it renews itself"), done)
                return
            }
            guard let token = Self.readToken() else {
                self.finish(.problem("Claude Code isn't signed in on this Mac, or Keychain access was denied"), done)
                return
            }
            if let exp = token.expiresAt, exp < Date() {
                self.finish(.problem("Claude Code's sign-in has expired. Open Claude Code once and it renews itself"), done)
                return
            }
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 20)
            req.setValue("Bearer \(token.access)", forHTTPHeaderField: "Authorization")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("claude-cli/2.1 (external, cli)", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { data, resp, err in
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if let err { self.finish(.problem("Couldn't reach Anthropic: \(err.localizedDescription)"), done); return }
                if code == 429 {
                    let header = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                    let retry = header ?? 600
                    let until = Date().addingTimeInterval(max(retry, 300))
                    self.lock.lock(); self.backoffUntil = until; self.lock.unlock()
                    self.persist {
                        $0.backoffUntil = until
                        $0.limits = Array((($0.limits ?? []) + [LimitHit(at: Date(), retryAfter: header)]).suffix(Self.keptLimitHits))
                    }
                    self.finish(.problem("Anthropic asked Reset to slow down; trying again in a few minutes"), done)
                    return
                }
                if code == 401 || code == 403 {
                    self.finish(.problem("Anthropic didn't accept the sign-in (HTTP \(code))"), done)
                    return
                }
                guard code == 200, let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.finish(.problem("Unexpected reply from Anthropic (HTTP \(code))"), done)
                    return
                }
                let snap = Snapshot(fiveHour: Self.window(obj["five_hour"]), sevenDay: Self.window(obj["seven_day"]), fetchedAt: Date())
                self.persist { $0.lastGood = snap }
                // Diagnostics: the usage windows exactly as received (percentages and reset times only).
                var diag: [String: Any] = ["fetched": ISO8601DateFormatter().string(from: Date())]
                for k in ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"] { diag[k] = obj[k] ?? NSNull() }
                if let d = try? JSONSerialization.data(withJSONObject: diag, options: [.prettyPrinted, .sortedKeys]) {
                    try? d.write(to: WidgetSnapshot.url.deletingLastPathComponent().appendingPathComponent("live-usage.json"))
                }
                DispatchQueue.main.async {
                    self.needsSignIn = false
                    self.snapshot = snap
                    self.state = snap.fiveHour == nil && snap.sevenDay == nil
                        ? .problem("Signed in, but Anthropic reports no usage windows for this account")
                        : .ok(snap.fetchedAt)
                    done()
                }
            }.resume()
        }
    }

    /// Fetch again right away, e.g. after the user signs Claude Code back in.
    func retryNow(done: @escaping () -> Void) {
        // Asked for by the user (after signing in), so it overrides the schedule, saved one included.
        lock.lock(); lastAttempt = .distantPast; backoffUntil = .distantPast; lock.unlock()
        persist { $0.lastAttempt = .distantPast; $0.backoffUntil = .distantPast }
        poll(interval: 0, done: done)
    }

    func reset() {
        needsSignIn = false
        lock.lock(); lastAttempt = .distantPast; backoffUntil = .distantPast; lock.unlock()
        // Switched off: forget the last reading too, so switching back on never shows something stale.
        persist { $0.lastGood = nil }
        snapshot = nil
        state = .off
    }

    private func finish(_ s: State, _ done: @escaping () -> Void) {
        if case .problem(let why) = s {
            let w = why.lowercased()
            needsSignIn = w.contains("sign-in") || w.contains("signed in") || w.contains("didn't accept")
        }
        if case .problem(let why) = s {
            let diag: [String: Any] = ["fetched": ISO8601DateFormatter().string(from: Date()), "problem": why]
            if let d = try? JSONSerialization.data(withJSONObject: diag, options: .prettyPrinted) {
                try? d.write(to: WidgetSnapshot.url.deletingLastPathComponent().appendingPathComponent("live-usage.json"))
            }
        }
        DispatchQueue.main.async { self.state = s; done() }
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let iso = ISO8601DateFormatter()

    static func window(_ v: Any?) -> Window? {
        guard let d = v as? [String: Any], let u = d["utilization"] as? Double else { return nil }
        let r = (d["resets_at"] as? String).flatMap { isoFrac.date(from: $0) ?? iso.date(from: $0) }
        return Window(percent: u, resetsAt: r)
    }

    struct Token { var access: String; var expiresAt: Date? }

    /// Uses /usr/bin/security, the same tool Claude Code writes the item with.
    static func readToken() -> Token? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String else { return nil }
        let exp = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Token(access: access, expiresAt: exp)
    }

    /// Overlays live numbers on the transcript-based status.
    func apply(to s: inout WindowStatus, now: Date) {
        guard let snap = snapshot, now.timeIntervalSince(snap.fetchedAt) < 15 * 60 else { return }
        if let fh = snap.fiveHour {
            s.usedPercent = fh.percent
            // A reading can be up to 15 minutes old (polling slows when idle or when asked to); past 3 minutes the
            // menu says how old, rather than passing it off as current.
            s.usageAsOf = now.timeIntervalSince(snap.fetchedAt) > 180 ? snap.fetchedAt : nil
            if let r = fh.resetsAt, r > now { s.state = .active(resetsAt: r) }
            else if fh.percent == 0 { s.state = .ready }
            s.isEstimate = false
            s.source = "Live from your Claude account"
        }
        // Live weekly data is authoritative both ways: it sets the block when the limit is used up,
        // and clears a stale one (for example from an old transcript limit row) once it isn't.
        if let sd = snap.sevenDay {
            if let r = sd.resetsAt, r > now {
                s.secondary = .init(label: "Weekly", resetsAt: r, usedPercent: sd.percent)
                s.blockedUntil = sd.percent >= 100 ? r : nil
            } else {
                s.blockedUntil = nil
            }
        }
    }
}
