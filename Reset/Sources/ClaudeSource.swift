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
        var status = WindowStatus(id: id, name: "Claude", state: .ready, usedPercent: nil,
                                  isEstimate: true, source: "Estimated from Claude Code activity", secondary: nil,
                                  canAutoStart: true)
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard FileManager.default.fileExists(atPath: root.path) else {
            status.state = .unavailable("No ~/.claude/projects folder")
            return status
        }

        // Widen the lookback until the oldest activity follows a gap of at least one window, so the chain of
        // windows is anchored at a real start rather than wherever the scan happened to begin.
        var lookback = 2 * Self.window
        let maxLookback: TimeInterval = 7 * 86400
        var events: [TranscriptScanner.Event] = []
        while true {
            let horizon = now.addingTimeInterval(-lookback)
            events = Self.scanner.events(under: root, since: horizon)
            events += extraStarts.filter { $0 > horizon && $0 <= now }.map { .init(time: $0, kind: .activity) }
            events.sort { $0.time < $1.time }
            let firstActivity = events.first { $0.kind == .activity }?.time
            guard let first = firstActivity, first < horizon.addingTimeInterval(Self.window),
                  lookback < maxLookback else { break }
            lookback = min(lookback * 2, maxLookback)
        }

        let activity = events.filter { $0.kind == .activity }.map(\.time)
        let result = Self.compute(events: events, activity: activity, now: now)
        if let w = result.window {
            status.state = .active(resetsAt: w.end)
            status.isEstimate = !w.exact
            if w.exact { status.source = "Exact, from Claude Code's limit message" }
        }
        if let weekly = result.weeklyBlockUntil {
            status.secondary = .init(label: "Weekly limit hit", resetsAt: weekly, usedPercent: 100)
            status.blockedUntil = weekly
        }

        // Real usage % from the Claude desktop app's own log, for the account Claude Code is signed in to.
        // A reading only counts if it was taken inside the current window; older ones describe a past window.
        if let org = Self.currentOrg(under: root), let sample = PlanUsageLog.latest(org: org) {
            let windowStart = status.resetsAt?.addingTimeInterval(-Self.window)
            // The desktop app only logs at moments like a window starting or the limit being hit, so a reading
            // is only trusted while fresh. A limit hit stays true for the rest of its window.
            if let ws = windowStart, sample.time >= ws,
               now.timeIntervalSince(sample.time) < 15 * 60 || sample.fiveHour >= 100 {
                status.usedPercent = sample.fiveHour
                status.usageAsOf = sample.time
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

    static func latest(org: String) -> Sample? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
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
    }

    private struct Entry { var mtime: Date; var size: Int; var events: [Event] }
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
            } else {
                entry = Entry(mtime: mod, size: size, events: Self.parse(url))
                cache[url.path] = entry
            }
            out += entry.events.filter { $0.time >= since }
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

    static func parse(_ url: URL) -> [Event] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
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
        return out
    }

    private static func timestamp(_ line: Data.SubSequence, key: Data) -> Date? {
        guard let r = line.range(of: key) else { return nil }
        let start = r.upperBound
        guard let end = line[start...].firstIndex(of: UInt8(ascii: "\"")),
              let s = String(data: line[start..<end], encoding: .utf8) else { return nil }
        return iso.date(from: s)
    }
}
