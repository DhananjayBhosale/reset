import Foundation

/// One billed Claude API response, after de-duplication.
struct Call: Codable {
    var id: String
    var time: Date
    var model: String
    var session: String
    var project: String
    var sidechain: Bool
    var input: Int
    var cw5: Int
    var cw1h: Int
    var cacheRead: Int
    var output: Int
    var advisorTokens: Int
    var tools: Int
    var mcpServers: [String: Int]
    var webSearches: Int
    var mcpAttribution: String?
    var cost: Double
    var autoStart: Bool

    var totalTokens: Int { input + cw5 + cw1h + cacheRead + output + advisorTokens }
    var mcpCalls: Int { mcpServers.values.reduce(0, +) }
}

/// Reads token usage from Claude Code transcripts. Streaming writes one row per content block with the
/// same message id; earlier rows carry placeholder output counts, so the row with the largest output wins.
/// Resumed and forked sessions copy rows between files, so de-duplication is global.
final class ClaudeUsageScanner {
    struct FileResult: Codable {
        var mtime: Date
        var size: Int
        var calls: [Call]
        var titles: [String: String]
        var limitHits: [Date]
        var apiMillis: [String: Int]
    }

    private var cache: [String: FileResult] = [:]
    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Reset", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("claude-usage-cache-v1.json")
    }()
    private var loadedDisk = false

    struct Result {
        var calls: [Call]
        var titles: [String: String]
        var limitHits: [Date]
        var apiMillis: [String: Int]
    }

    func scan(since: Date) -> Result {
        if !loadedDisk {
            loadedDisk = true
            if let d = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode([String: FileResult].self, from: d) { cache = c }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [home.appendingPathComponent(".claude/projects"),
                     home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions")]
        var seen: Set<String> = []
        var changed = false
        var results: [FileResult] = []
        for root in roots {
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                                         options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in e where url.pathExtension == "jsonl" && url.lastPathComponent != "audit.jsonl" {
                let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                guard let mod = rv?.contentModificationDate, mod >= since else { continue }
                let size = rv?.fileSize ?? 0
                seen.insert(url.path)
                if let c = cache[url.path], c.mtime == mod, c.size == size { results.append(c); continue }
                let r = Self.parse(url, mtime: mod, size: size)
                cache[url.path] = r
                results.append(r)
                changed = true
            }
        }
        if changed {
            cache = cache.filter { seen.contains($0.key) }
            if let d = try? JSONEncoder().encode(cache) { try? d.write(to: cacheURL, options: .atomic) }
        }
        // Global de-duplication by message id: keep the copy with the most output, attributed to the
        // earliest time seen.
        var best: [String: Call] = [:]
        var titles: [String: String] = [:]
        var hits: [Date] = []
        var api: [String: Int] = [:]
        for r in results {
            for c in r.calls {
                if let b = best[c.id] {
                    if c.output > b.output { var n = c; n.time = min(c.time, b.time); best[c.id] = n }
                    else if c.time < b.time { var n = b; n.time = c.time; best[c.id] = n }
                } else { best[c.id] = c }
            }
            titles.merge(r.titles) { a, _ in a }
            hits += r.limitHits
            api.merge(r.apiMillis) { max($0, $1) }
        }
        return Result(calls: best.values.filter { $0.time >= since }.sorted { $0.time < $1.time },
                      titles: titles, limitHits: hits.sorted(), apiMillis: api)
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    static func parse(_ url: URL, mtime: Date, size: Int) -> FileResult {
        var out = FileResult(mtime: mtime, size: size, calls: [], titles: [:], limitHits: [], apiMillis: [:])
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return out }
        let isKickFile = url.path.contains("Application-Support-Reset-kick")
        let mAssistant = Data("\"type\":\"assistant\"".utf8)
        let mTitle = Data("-title\"".utf8)
        let mCost = Data("\"type\":\"cost-state\"".utf8)
        var bestById: [String: Call] = [:]
        for line in data.split(separator: UInt8(ascii: "\n")) {
            let isAssistant = line.range(of: mAssistant) != nil
            let isTitle = !isAssistant && line.range(of: mTitle) != nil
            let isCost = !isAssistant && line.range(of: mCost) != nil
            guard isAssistant || isTitle || isCost,
                  let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            let session = obj["sessionId"] as? String ?? url.deletingPathExtension().lastPathComponent
            if isTitle {
                if let t = obj["customTitle"] as? String { out.titles[session] = t }
                else if let t = obj["aiTitle"] as? String, out.titles[session] == nil { out.titles[session] = t }
                continue
            }
            if isCost {
                if let ms = obj["totalAPIDuration"] as? Int { out.apiMillis[session] = max(out.apiMillis[session] ?? 0, ms) }
                continue
            }
            guard let ts = (obj["timestamp"] as? String).flatMap({ isoFrac.date(from: $0) }) else { continue }
            if let q = obj["quotaLimits"] as? [String: Any], (q["rateLimitType"] as? String) == "five_hour" {
                out.limitHits.append(ts)
                continue
            }
            if (obj["isApiErrorMessage"] as? Bool) == true { continue }
            guard let msg = obj["message"] as? [String: Any], let id = msg["id"] as? String,
                  let model = msg["model"] as? String, model != "<synthetic>",
                  let u = msg["usage"] as? [String: Any] else { continue }
            func i(_ d: [String: Any]?, _ k: String) -> Int { (d?[k] as? Int) ?? 0 }
            let cc = u["cache_creation"] as? [String: Any]
            var cw5 = i(cc, "ephemeral_5m_input_tokens"), cw1h = i(cc, "ephemeral_1h_input_tokens")
            if cc == nil { cw5 = i(u, "cache_creation_input_tokens") }
            let input = i(u, "input_tokens"), cr = i(u, "cache_read_input_tokens"), output = i(u, "output_tokens")
            var cost = Pricing.claude(model).map { Pricing.cost($0, input: input, cw5: cw5, cw1h: cw1h, cacheRead: cr, output: output) } ?? 0
            // Advisor calls are billed separately and only appear in `iterations`.
            var advisorTokens = 0
            for it in u["iterations"] as? [[String: Any]] ?? [] where (it["type"] as? String) == "advisor_message" {
                let am = it["model"] as? String ?? model
                let ai = i(it, "input_tokens"), ao = i(it, "output_tokens"), acr = i(it, "cache_read_input_tokens")
                let acc = it["cache_creation"] as? [String: Any]
                let a5 = i(acc, "ephemeral_5m_input_tokens"), a1 = i(acc, "ephemeral_1h_input_tokens")
                advisorTokens += ai + ao + acr + a5 + a1
                if let p = Pricing.claude(am) { cost += Pricing.cost(p, input: ai, cw5: a5, cw1h: a1, cacheRead: acr, output: ao) }
            }
            var tools = 0, web = (u["server_tool_use"] as? [String: Any]).map { i($0, "web_search_requests") } ?? 0
            var servers: [String: Int] = [:]
            for block in msg["content"] as? [[String: Any]] ?? [] {
                guard let type = block["type"] as? String else { continue }
                if type == "tool_use", let name = block["name"] as? String {
                    tools += 1
                    if name.hasPrefix("mcp__") {
                        let server = name.dropFirst(5).components(separatedBy: "__").first ?? "mcp"
                        servers[server, default: 0] += 1
                    }
                    if name == "WebSearch" { web += 1 }
                }
            }
            let call = Call(id: id, time: ts, model: model, session: session, project: obj["cwd"] as? String ?? "",
                            sidechain: (obj["isSidechain"] as? Bool) ?? false, input: input, cw5: cw5, cw1h: cw1h,
                            cacheRead: cr, output: output, advisorTokens: advisorTokens, tools: tools, mcpServers: servers,
                            webSearches: web, mcpAttribution: obj["attributionMcpServer"] as? String, cost: cost,
                            autoStart: isKickFile)
            if let b = bestById[id] {
                // Same response streamed over several rows: tools accumulate, usage takes the final row.
                var n = call.output >= b.output ? call : b
                n.tools = b.tools + call.tools
                n.mcpServers = b.mcpServers.merging(call.mcpServers, uniquingKeysWith: +)
                n.webSearches = max(b.webSearches, call.webSearches)
                n.time = min(b.time, call.time)
                bestById[id] = n
            } else {
                bestById[id] = call
            }
        }
        out.calls = Array(bestById.values)
        return out
    }
}
