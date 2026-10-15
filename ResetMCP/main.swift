import Foundation

// A minimal MCP server over stdio (newline-delimited JSON-RPC 2.0). It lets Claude Code ask Reset how much
// of the usage window is left, so an agent can pace itself. It only reads the snapshot Reset writes; it never
// touches credentials or the network.

setvbuf(stdout, nil, _IOLBF, 0)

func send(_ obj: [String: Any]) {
    guard let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { return }
    print(s)
}

let iso = ISO8601DateFormatter()

/// Money as an exact two-decimal JSON number, without binary float noise.
func usd(_ v: Double) -> NSDecimalNumber { NSDecimalNumber(string: String(format: "%.2f", v)) }
let local: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f }()

func usageReport() -> [String: Any] {
    guard let snap = WidgetSnapshot.load() else {
        return ["error": "Reset isn't running or hasn't written usage yet. Open Reset.app."]
    }
    let now = Date()
    var out: [String: Any] = ["updated": iso.string(from: snap.updated)]
    if let c = snap.claude {
        var claude: [String: Any] = [:]
        let ready = c.ready || (c.resetsAt.map { $0 <= now } ?? false)
        claude["window"] = ready ? "fresh window ready" : "active"
        if let u = c.used, !ready {
            claude["percent_used"] = Int(u.rounded())
            claude["percent_left"] = Int((100 - u).rounded())
        }
        if let r = c.resetsAt, r > now {
            claude["resets_at"] = iso.string(from: r)
            claude["resets_at_local"] = local.string(from: r)
            claude["minutes_until_reset"] = Int(r.timeIntervalSince(now) / 60)
        }
        if let b = c.blockedUntil, b > now { claude["weekly_limit_until"] = iso.string(from: b) }
        if let o = snap.claudeRunsOutAt, o > now {
            claude["projected_run_out_local"] = local.string(from: o)
            claude["minutes_until_run_out"] = Int(o.timeIntervalSince(now) / 60)
        }
        out["claude"] = claude
        // Plain-language advice an agent can act on.
        let left = ready ? 100.0 : (c.used.map { 100 - $0 } ?? 100)
        if let b = c.blockedUntil, b > now {
            out["advice"] = "The weekly limit is exhausted until \(local.string(from: b)). Pause non-essential work."
        } else if snap.claudeRunsOutAt != nil || left < 15 {
            out["advice"] = "Window nearly exhausted. Finish the current step, prefer smaller models for subagents, avoid broad fan-outs until the reset."
        } else if left < 40 {
            out["advice"] = "Under half the window left. Keep subagents lean and batch tool calls."
        } else {
            out["advice"] = "Plenty of window left."
        }
    }
    var cost: [String: Any] = ["last_7_days_usd": usd(snap.weekCost)]
    if let t = snap.todayCumulative?.last { cost["today_usd"] = usd(t) }
    if let m = snap.monthCost { cost["last_30_days_usd"] = usd(m) }
    cost["note"] = "API list-price value of Claude Code usage, not a bill."
    out["cost"] = cost
    return out
}

let tools: [[String: Any]] = [[
    "name": "get_claude_usage",
    "description": "How much of the Claude usage window is left, when it resets, whether it will run out first at the current pace, and today's API-value spend. Use it before starting large or parallel work.",
    "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
]]

while let line = readLine(strippingNewline: true) {
    guard let data = line.data(using: .utf8),
          let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let method = msg["method"] as? String else { continue }
    let id = msg["id"]
    func reply(_ result: [String: Any]) { if let id { send(["jsonrpc": "2.0", "id": id, "result": result]) } }
    switch method {
    case "initialize":
        let requested = (msg["params"] as? [String: Any])?["protocolVersion"] as? String ?? "2025-06-18"
        reply(["protocolVersion": requested, "capabilities": ["tools": [String: Any]()],
               "serverInfo": ["name": "reset", "version": "0.1"]])
    case "tools/list":
        reply(["tools": tools])
    case "tools/call":
        let name = (msg["params"] as? [String: Any])?["name"] as? String
        if name == "get_claude_usage" {
            let r = usageReport()
            let text = (try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            reply(["content": [["type": "text", "text": text]], "isError": r["error"] != nil])
        } else if let id {
            send(["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Unknown tool"]])
        }
    case "ping":
        reply([:])
    default:
        if id != nil, !method.hasPrefix("notifications/") {
            send(["jsonrpc": "2.0", "id": id!, "error": ["code": -32601, "message": "Method not found"]])
        }
    }
}
