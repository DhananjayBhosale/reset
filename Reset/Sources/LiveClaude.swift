import Foundation

/// Opt-in exact Claude usage: reads Claude Code's own sign-in from the Keychain and asks Anthropic's usage
/// endpoint for the current 5-hour and weekly windows. Only usage numbers are fetched, the token is only
/// ever sent to api.anthropic.com, and Reset never refreshes or rewrites it (that would sign Claude Code out).
final class LiveClaude {
    struct Window { var percent: Double; var resetsAt: Date? }
    struct Snapshot { var fiveHour: Window?; var sevenDay: Window?; var fetchedAt: Date }

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

    /// Fetch if the last one is older than `interval`. Calls `done` on the main queue when something changed.
    func poll(interval: TimeInterval = 180, done: @escaping () -> Void) {
        lock.lock()
        let now = Date()
        guard now.timeIntervalSince(lastAttempt) >= interval, now >= backoffUntil else { lock.unlock(); return }
        lastAttempt = now
        lock.unlock()
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
                    let retry = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 600
                    self.lock.lock(); self.backoffUntil = Date().addingTimeInterval(max(retry, 300)); self.lock.unlock()
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
        lock.lock(); lastAttempt = .distantPast; backoffUntil = .distantPast; lock.unlock()
        poll(interval: 0, done: done)
    }

    func reset() {
        needsSignIn = false
        lock.lock(); lastAttempt = .distantPast; backoffUntil = .distantPast; lock.unlock()
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
            s.usageAsOf = nil
            if let r = fh.resetsAt, r > now { s.state = .active(resetsAt: r) }
            else if fh.percent == 0 { s.state = .ready }
            s.isEstimate = false
            s.source = "Live from your Claude account"
        }
        if let sd = snap.sevenDay, let r = sd.resetsAt, r > now {
            s.secondary = .init(label: "Weekly", resetsAt: r, usedPercent: sd.percent)
            if sd.percent >= 100 { s.blockedUntil = r }
        }
    }
}
