import Foundation

/// Antigravity's quota, read from its own language server while the app is running. The server listens on
/// 127.0.0.1 and takes a per-launch CSRF token that it was started with; Reset reads both from the
/// process list, asks for the quota summary, and never sends anything off this Mac.
struct AntigravitySource: WindowSource {
    let id = "antigravity"

    func read(now: Date) -> WindowStatus {
        var status = WindowStatus(id: id, name: "Antigravity", state: .unavailable("Open Antigravity to read its usage"),
                                  usedPercent: nil, isEstimate: false, source: "Antigravity, live while the app is open",
                                  secondary: nil, canAutoStart: false)
        // Closed: show the last reading if its window is still running, rather than nothing until it's reopened.
        guard let server = Self.findServer() else { return Self.lastSeen(Self.loadCache(), now: now) ?? status }
        guard let summary = Self.quotaSummary(server) else {
            status.state = .unavailable("Antigravity is open but didn't share its usage")
            return status
        }
        // Several model groups (Gemini; Claude and GPT), each with a 5-hour session bucket and a weekly one.
        // The mascot follows whichever session bucket is closest to empty.
        let session = summary.filter { !$0.weekly }.min { $0.remaining < $1.remaining }
        let weekly = summary.filter { $0.weekly }.min { $0.remaining < $1.remaining }
        if let s = session {
            status.usedPercent = (1 - s.remaining) * 100
            if let r = s.resetsAt, r > now { status.state = .active(resetsAt: r) } else { status.state = .ready }
            status.source = "Antigravity · \(s.group)"
        } else {
            status.state = .ready
        }
        if let w = weekly, let r = w.resetsAt, r > now {
            status.secondary = .init(label: "Weekly", resetsAt: r, usedPercent: (1 - w.remaining) * 100)
            if w.remaining <= 0.001 { status.blockedUntil = r }
        }
        Self.saveCache(Cached(seenAt: now, resetsAt: status.resetsAt, usedPercent: status.usedPercent, group: session?.group,
                              weeklyResetsAt: status.secondary?.resetsAt, weeklyUsed: status.secondary?.usedPercent,
                              blockedUntil: status.blockedUntil))
        return status
    }

    // MARK: Last reading, for while Antigravity is closed

    /// The last good reading, saved each time the app answers. Only reset times and percentages.
    struct Cached: Codable, Equatable {
        var seenAt: Date
        var resetsAt: Date?
        var usedPercent: Double?
        var group: String?
        var weeklyResetsAt: Date?
        var weeklyUsed: Double?
        var blockedUntil: Date?
    }

    static var cacheURL: URL { WidgetSnapshot.url.deletingLastPathComponent().appendingPathComponent("antigravity-last.json") }

    static func saveCache(_ c: Cached) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        guard let d = try? enc.encode(c) else { return }
        try? d.write(to: cacheURL, options: .atomic)
    }

    static func loadCache() -> Cached? {
        guard let d = try? Data(contentsOf: cacheURL) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(Cached.self, from: d)
    }

    /// A status from the last reading, while its window (or a weekly limit) is still running. The reset time is
    /// what the app reported, so it stays exact; the percentage is as of when it was seen, and says so.
    static func lastSeen(_ c: Cached?, now: Date) -> WindowStatus? {
        guard let c else { return nil }
        let blocked = c.blockedUntil.map { $0 > now } ?? false
        guard (c.resetsAt.map { $0 > now } ?? false) || blocked else { return nil }
        var s = WindowStatus(id: "antigravity", name: "Antigravity", state: .ready, usedPercent: c.usedPercent, isEstimate: false,
                             source: "Last seen \(Fmt.when(c.seenAt, now: now)) while Antigravity was open",
                             secondary: nil, canAutoStart: false)
        if let r = c.resetsAt, r > now { s.state = .active(resetsAt: r) }
        s.usageAsOf = c.seenAt
        if let w = c.weeklyResetsAt, w > now { s.secondary = .init(label: "Weekly", resetsAt: w, usedPercent: c.weeklyUsed) }
        if blocked { s.blockedUntil = c.blockedUntil }
        return s
    }

    struct Server { var pid: Int32; var csrf: String; var extensionPort: Int?; var extensionCsrf: String? }
    struct Bucket { var group: String; var remaining: Double; var resetsAt: Date?; var weekly: Bool }

    static func findServer() -> Server? {
        guard let out = run("/bin/ps", ["-ax", "-o", "pid=,command="]) else { return nil }
        for line in out.split(separator: "\n") where line.contains("Antigravity.app") && line.contains("language_server") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
            // The IDE variant serves a different API; the main app runs with --app_data_dir antigravity.
            if let i = parts.firstIndex(of: "--app_data_dir"), i + 1 < parts.count, parts[i + 1] != "antigravity" { continue }
            func flag(_ name: String) -> String? {
                guard let i = parts.firstIndex(of: name), i + 1 < parts.count else { return nil }
                return parts[i + 1]
            }
            guard let pid = Int32(parts.first ?? ""), let csrf = flag("--csrf_token") else { continue }
            return Server(pid: pid, csrf: csrf, extensionPort: flag("--extension_server_port").flatMap(Int.init),
                          extensionCsrf: flag("--extension_server_csrf_token"))
        }
        return nil
    }

    static func listeningPorts(_ pid: Int32) -> [Int] {
        guard let out = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", String(pid)]) else { return [] }
        var ports: [Int] = []
        for line in out.split(separator: "\n").dropFirst() {
            if let name = line.split(separator: " ").last(where: { $0.contains(":") }),
               let p = Int(name.split(separator: ":").last ?? "") { ports.append(p) }
        }
        return Array(Set(ports)).sorted()
    }

    private static var cachedPort: (pid: Int32, port: Int, https: Bool)?

    static func quotaSummary(_ s: Server) -> [Bucket]? {
        var candidates: [(Int, Bool, String)] = []
        if let c = cachedPort, c.pid == s.pid { candidates.append((c.port, c.https, s.csrf)) }
        for p in listeningPorts(s.pid) { candidates.append((p, true, s.csrf)) }
        if let ep = s.extensionPort { candidates.append((ep, false, s.extensionCsrf ?? s.csrf)) }
        for (port, https, token) in candidates {
            if let body = post(port: port, https: https, csrf: token, method: "RetrieveUserQuotaSummary", body: ["forceRefresh": true]),
               let buckets = parse(body) {
                cachedPort = (s.pid, port, https)
                return buckets
            }
        }
        return nil
    }

    static func parse(_ obj: [String: Any]) -> [Bucket]? {
        let root = (obj["response"] as? [String: Any]) ?? (obj["summary"] as? [String: Any]) ?? obj
        let summary = (root["summary"] as? [String: Any]) ?? root
        guard let groups = summary["groups"] as? [[String: Any]] else { return nil }
        let iso = ISO8601DateFormatter()
        let isoFrac = ISO8601DateFormatter(); isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var out: [Bucket] = []
        for g in groups {
            let gname = g["displayName"] as? String ?? "Models"
            for b in g["buckets"] as? [[String: Any]] ?? [] where (b["disabled"] as? Bool) != true {
                let rem = (b["remaining"] as? [String: Any])?["remainingFraction"] as? Double ?? 1
                let reset = (b["resetTime"] as? String).flatMap { isoFrac.date(from: $0) ?? iso.date(from: $0) }
                let label = [b["window"], b["bucketId"], b["displayName"]].compactMap { $0 as? String }.joined(separator: " ").lowercased()
                out.append(Bucket(group: gname, remaining: rem, resetsAt: reset, weekly: label.contains("week")))
            }
        }
        return out.isEmpty ? nil : out
    }

    /// The language server uses a self-signed certificate, so trust is limited to 127.0.0.1.
    private final class LocalTrust: NSObject, URLSessionDelegate {
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.host == "127.0.0.1", let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
    private static let session = URLSession(configuration: .ephemeral, delegate: LocalTrust(), delegateQueue: nil)

    static func post(port: Int, https: Bool, csrf: String, method: String, body: [String: Any]) -> [String: Any]? {
        let url = URL(string: "\(https ? "https" : "http")://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/\(method)")!
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "POST"
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        req.setValue(csrf, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        var result: [String: Any]?
        let sem = DispatchSemaphore(value: 0)
        session.dataTask(with: req) { data, resp, _ in
            if (resp as? HTTPURLResponse)?.statusCode == 200, let data {
                result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 4)
        return result
    }

    static func run(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
