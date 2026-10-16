import Foundation

/// Claude's 5-hour session window, rebuilt from Claude Code transcripts in ~/.claude/projects.
///
/// Two kinds of evidence:
/// - Exact: when a limit is hit, Claude Code logs an error row with `quotaLimits.resetsAt` (epoch seconds)
///   and `rateLimitType` (five_hour or seven_day). That is the real reset time.
/// - Estimate: otherwise a window opens at the first successful API response after the previous window
///   ended, floored to 10 minutes (every exact reset logged on this Mac sits on a 10-minute mark), and runs 5h.
///
/// Usage on claude.ai or the desktop chat is invisible here, so `extraStarts` lets the user add it.
struct ClaudeSource: WindowSource {
    let id = "claude"
    static let window: TimeInterval = 5 * 3600
    static let scanner = TranscriptScanner()

    var extraStarts: [Date] = []

    func read(now: Date) -> WindowStatus {
        readAll(now: now, account: nil)[0]
    }

    /// One status per Claude account seen in the transcripts: "claude" for the account the Claude Code CLI is
    /// signed in to (live usage, auto-start and budgets go through the CLI), and "claude-<org>" for any other
    /// account used in the last week, each with its own window from its own sessions. With one account there's
    /// just "Claude", as before.
    func readAll(now: Date, account: ClaudeCLI.Account?) -> [WindowStatus] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard FileManager.default.fileExists(atPath: root.path) else {
            var s = WindowStatus(id: id, name: "Claude", state: .unavailable("No ~/.claude/projects folder"), usedPercent: nil,
                                 isEstimate: true, source: "Estimated from Claude Code activity", secondary: nil, canAutoStart: true)
            s.lastActivity = nil
            return [s]
        }

        // A week of events from every account, to find the accounts and give the others their windows.
        let week = Self.scanner.events(under: root, since: now.addingTimeInterval(-Self.otherLookback))
        let main = Self.mainOrg(cliOrg: account?.orgId, events: week)

        // Widen the lookback until the oldest activity follows a gap of at least one window, so the chain of
        // windows is anchored at a real start rather than wherever the scan happened to begin.
        var lookback = 2 * Self.window
        let maxLookback: TimeInterval = 7 * 86400
        var events: [TranscriptScanner.Event] = []
        while true {
            let horizon = now.addingTimeInterval(-lookback)
            // Only the main account's sessions (and untagged ones, such as "I used Claude on the web").
            events = Self.scanner.events(under: root, since: horizon).filter { $0.org == nil || $0.org == main }
            events += extraStarts.filter { $0 > horizon && $0 <= now }.map { .init(time: $0, kind: .activity) }
            events.sort { $0.time < $1.time }
            let firstActivity = events.first { $0.kind == .activity }?.time
            guard let first = firstActivity, first < horizon.addingTimeInterval(Self.window),
                  lookback < maxLookback else { break }
            lookback = min(lookback * 2, maxLookback)
        }

        let others = Self.otherOrgs(events: week, main: main)
        var mainStatus = Self.status(id: id, name: "Claude", events: events, org: main ?? Self.currentOrg(under: root), now: now,
                                     canAutoStart: true)
        if !others.isEmpty, let label = Self.planLabel(account?.plan) { mainStatus.name = "Claude · \(label)" }
        var out = [mainStatus]
        for org in others {
            let mine = week.filter { $0.org == org }.sorted { $0.time < $1.time }
            // Auto-start runs through the CLI, which is signed in to the main account, so it can't start these.
            var s = Self.status(id: "claude-" + org.prefix(8), name: "Claude · " + Self.otherLabel(org: org), events: mine,
                                org: org, now: now, canAutoStart: false)
            // Say whose sessions it's estimated from, keeping anything appended (such as a used-up weekly limit).
            if s.isEstimate, s.source.hasPrefix("Estimated from Claude Code activity") {
                s.source = "Estimated from this account's Claude Code sessions" + s.source.dropFirst("Estimated from Claude Code activity".count)
            }
            out.append(s)
        }
        return out
    }

    /// Other accounts count if they were used in the last week; older ones have no window to show.
    static let otherLookback: TimeInterval = 7 * 86400

    /// The CLI's account when known, otherwise the account of the most recent activity.
    static func mainOrg(cliOrg: String?, events: [TranscriptScanner.Event]) -> String? {
        if let cliOrg { return cliOrg }
        return events.filter { $0.kind == .activity && $0.org != nil }.max { $0.time < $1.time }?.org
    }

    /// Accounts other than the main one with real activity in the events, most recently used first.
    static func otherOrgs(events: [TranscriptScanner.Event], main: String?) -> [String] {
        var last: [String: Date] = [:]
        for e in events where e.kind == .activity {
            guard let o = e.org, o != main else { continue }
            last[o] = max(last[o] ?? .distantPast, e.time)
        }
        return last.sorted { $0.value > $1.value }.map(\.key)
    }

    /// "team" → "Team" and so on, for naming the main entry when there's more than one account.
    static func planLabel(_ plan: String?) -> String? {
        guard let p = plan?.trimmingCharacters(in: .whitespaces), !p.isEmpty else { return nil }
        return p.prefix(1).uppercased() + p.dropFirst()
    }

    /// The other account's plan isn't written anywhere Reset reads, but only Pro and Max plans have a weekly
    /// limit, which the Claude desktop app logs for them; Team and Enterprise ones don't.
    static func otherLabel(org: String, url: URL = PlanUsageLog.url) -> String {
        PlanUsageLog.latest(org: org, url: url)?.sevenDay != nil ? "Pro" : "other account"
    }

    /// The window, limit hits and desktop-app reading for one account's events.
    static func status(id: String, name: String, events: [TranscriptScanner.Event], org: String?, now: Date,
                       canAutoStart: Bool) -> WindowStatus {
        var status = WindowStatus(id: id, name: name, state: .ready, usedPercent: nil, isEstimate: true,
                                  source: "Estimated from Claude Code activity", secondary: nil, canAutoStart: canAutoStart)
        status.account = org
        let activity = events.filter { $0.kind == .activity }.map(\.time)
        status.lastActivity = activity.last { $0 <= now }
        let result = compute(events: events, activity: activity, now: now)
        if let w = result.window {
            status.state = .active(resetsAt: w.end)
            status.isEstimate = !w.exact
            if w.exact { status.source = "Exact, from Claude Code's limit message" }
        }
        if let weekly = result.weeklyBlockUntil {
            status.secondary = .init(label: "Weekly limit hit", resetsAt: weekly, usedPercent: 100)
            status.blockedUntil = weekly
        }

        // Real usage % from the Claude desktop app's own log, for this account.
        // A reading only counts if it was taken inside the current window; older ones describe a past window.
        if let org, let sample = PlanUsageLog.latest(org: org) {
            let windowStart = status.resetsAt?.addingTimeInterval(-window)
            // The desktop app only logs at moments like a window starting or the limit being hit, so a reading
            // is only trusted while fresh. A limit hit stays true for the rest of its window.
            if let ws = windowStart, sample.time >= ws,
               now.timeIntervalSince(sample.time) < 15 * 60 || sample.fiveHour >= 100 {
                status.usedPercent = sample.fiveHour
                status.usageAsOf = sample.time
            }
            // A used-up weekly limit, when no limit message gave its reset time: say so rather than nothing.
            if status.blockedUntil == nil, let sd = sample.sevenDay, sd >= 100, now.timeIntervalSince(sample.time) < 7 * 86400 {
                status.source += " · weekly limit used up as of \(Fmt.when(sample.time, now: now))"
            }
        }
        return status
    }

    /// The organization of the most recently written transcript, from Claude Code's `credential_org` rows.
    static func currentOrg(under root: URL) -> String? {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                    options: [.skipsHiddenFiles]) else { return nil }
        var files: [(URL, Date)] = []
        let cutoff = Date().addingTimeInterval(-3 * 86400)
        for case let url as URL in e where url.pathExtension == "jsonl" {
            if let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, m > cutoff {
                files.append((url, m))
            }
        }
        let key = Data("\"organizationUuid\":\"".utf8)
        for (url, _) in files.sorted(by: { $0.1 > $1.1 }).prefix(8) {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let r = data.range(of: key, options: .backwards) else { continue }
            let rest = data[r.upperBound...]
            if let end = rest.firstIndex(of: UInt8(ascii: "\"")) { return String(data: rest[..<end], encoding: .utf8) }
        }
        return nil
    }

    struct Computed {
        var window: (end: Date, exact: Bool)?
        var weeklyBlockUntil: Date?
    }

    /// A limit row is trusted only if nothing succeeded after it before its reset; success in that span
    /// means another account or a lifted limit, so the row says nothing about the current window.
    static func isValid(_ t: Date, resetsAt: Date, activity: [Date]) -> Bool {
        !activity.contains { $0 > t.addingTimeInterval(120) && $0 < resetsAt }
    }

    static func compute(events: [TranscriptScanner.Event], activity: [Date], now: Date) -> Computed {
        var out = Computed()
        var start: Date?
        var end: Date?
        var exact = false
        for e in events where e.time <= now {
            switch e.kind {
            case .activity:
                if let en = end, e.time < en { continue }
                start = floorTo10(e.time)
                end = start!.addingTimeInterval(window)
                exact = false
            case .fiveHourLimit(let r):
                guard isValid(e.time, resetsAt: r, activity: activity) else { continue }
                start = r.addingTimeInterval(-window)
                end = r
                exact = true
            case .weeklyLimit(let r):
                if r > now, isValid(e.time, resetsAt: r, activity: activity) { out.weeklyBlockUntil = r }
            }
        }
        if let en = end, now < en { out.window = (en, exact) }
        return out
    }

    static func floorTo10(_ d: Date) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 600).rounded(.down) * 600)
    }
}

/// ~/Library/Application Support/Claude/plan-usage-history.json, written by the Claude desktop app:
/// samples of the 5-hour (`fh`) and 7-day (`sd`) usage percentage per organization.
enum PlanUsageLog {
    struct Sample { var time: Date; var fiveHour: Double; var sevenDay: Double? }

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")

    /// `url` is only ever not the desktop app's file in the format-drift fixtures.
    static func latest(org: String, url: URL = PlanUsageLog.url) -> Sample? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = obj["samples"] as? [[String: Any]] else { return nil }
        for s in samples.reversed() where (s["org"] as? String) == org {
            guard let t = s["t"] as? Double, let u = s["u"] as? [String: Any], let fh = u["fh"] as? Double else { continue }
            return Sample(time: Date(timeIntervalSince1970: t / 1000), fiveHour: fh, sevenDay: u["sd"] as? Double)
        }
        return nil
    }
}

/// Parses transcript rows into activity and limit events, caching each file by (mtime, size) so the
/// 60-second rescan only re-reads files that changed.
final class TranscriptScanner {
    struct Event: Equatable {
        enum Kind: Equatable {
            case activity
            case fiveHourLimit(Date)
            case weeklyLimit(Date)
        }
        var time: Date
        var kind: Kind
        /// The Claude organization (account) of the session the event came from, when its transcript says.
        var org: String? = nil
    }

    private struct Entry { var mtime: Date; var size: Int; var events: [Event]; var offset: Int; var org: String? }
    private var cache: [String: Entry] = [:]
    private let lock = NSLock()

    func events(under root: URL, since: Date) -> [Event] {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                    options: [.skipsHiddenFiles]) else { return [] }
        var out: [Event] = []
        var seen: Set<String> = []
        for case let url as URL in e where url.pathExtension == "jsonl" {
            let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let mod = rv?.contentModificationDate, mod >= since else { continue }
            let size = rv?.fileSize ?? 0
            seen.insert(url.path)
            let entry: Entry
            if let c = cache[url.path], c.mtime == mod, c.size == size {
                entry = c
            } else if let c = cache[url.path], size > c.offset, c.offset > 0 {
                // Transcripts only grow: read just the new lines.
                let (events, offset) = Self.parse(url, from: c.offset, size: size)
                entry = Entry(mtime: mod, size: size, events: c.events + events, offset: offset,
                              org: Self.lastOrg(url, from: c.offset, size: size) ?? c.org)
                cache[url.path] = entry
            } else {
                let (events, offset) = Self.parse(url, from: 0, size: size)
                entry = Entry(mtime: mod, size: size, events: events, offset: offset, org: Self.lastOrg(url, from: 0, size: size))
                cache[url.path] = entry
            }
            // A session runs under one account; its transcript's org applies to all its events.
            out += entry.events.filter { $0.time >= since }.map { var e = $0; e.org = entry.org; return e }
        }
        // Drop cache entries for files that aged out of every possible lookback.
        if cache.count > seen.count + 200 { cache = cache.filter { seen.contains($0.key) } }
        return out
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// The last `organizationUuid` Claude Code wrote in this part of a transcript (its credential rows).
    static func lastOrg(_ url: URL, from start: Int, size: Int) -> String? {
        guard let all = try? Data(contentsOf: url, options: .mappedIfSafe), all.count > start else { return nil }
        let data = all[start..<min(all.count, max(size, start))]
        let key = Data("\"organizationUuid\":\"".utf8)
        guard let r = data.range(of: key, options: .backwards) else { return nil }
        let rest = data[r.upperBound...]
        guard let end = rest.firstIndex(of: UInt8(ascii: "\"")) else { return nil }
        return String(data: rest[..<end], encoding: .utf8)
    }

    static func parse(_ url: URL, from start: Int, size: Int) -> ([Event], Int) {
        guard let all = try? Data(contentsOf: url, options: .mappedIfSafe), all.count > start else { return ([], start) }
        let end = min(all.count, max(size, start))
        guard end > start, let lastNewline = all[start..<end].lastIndex(of: UInt8(ascii: "\n")) else { return ([], start) }
        let data = all[start...lastNewline]
        let assistant = Data("\"type\":\"assistant\"".utf8)
        let quota = Data("\"quotaLimits\"".utf8)
        let isError = Data("\"isApiErrorMessage\":true".utf8)
        let requestId = Data("\"requestId\"".utf8)
        let key = Data("\"timestamp\":\"".utf8)
        var out: [Event] = []
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard line.range(of: assistant) != nil, let ts = timestamp(line, key: key) else { continue }
            if line.range(of: quota) != nil {
                if let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                   let q = obj["quotaLimits"] as? [String: Any], let r = q["resetsAt"] as? Double,
                   (q["status"] as? String) == "rejected" {
                    let at = Date(timeIntervalSince1970: r)
                    switch q["rateLimitType"] as? String {
                    case "five_hour": out.append(.init(time: ts, kind: .fiveHourLimit(at)))
                    case "seven_day", "seven_day_opus", "seven_day_sonnet": out.append(.init(time: ts, kind: .weeklyLimit(at)))
                    default: break
                    }
                }
                continue
            }
            // Only real API responses count as usage: error rows, slash-command echoes and synthetic
            // rows have no requestId or are flagged as API errors.
            guard line.range(of: isError) == nil, line.range(of: requestId) != nil else { continue }
            out.append(.init(time: ts, kind: .activity))
        }
        return (out, lastNewline + 1)
    }

    private static func timestamp(_ line: Data.SubSequence, key: Data) -> Date? {
        guard let r = line.range(of: key) else { return nil }
        let start = r.upperBound
        guard let end = line[start...].firstIndex(of: UInt8(ascii: "\"")),
              let s = String(data: line[start..<end], encoding: .utf8) else { return nil }
        return iso.date(from: s)
    }
}
