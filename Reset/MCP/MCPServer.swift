import Foundation

/// The reset-mcp request handler, kept apart from the stdio loop in ResetMCP/main.swift so the JSON-RPC
/// round-trips can be unit-tested without spawning a process. It is compiled into both the reset-mcp tool
/// and the app (which the tests are hosted in).
///
/// It reads the snapshot Reset writes and reads/writes budget.json. It never touches credentials or the network.
enum MCPServer {
    struct Environment {
        var now: () -> Date = Date.init
        var snapshot: () -> WidgetSnapshot? = WidgetSnapshot.load
        var budgetURL: URL = Budget.url
    }

    /// One NDJSON line in, at most one line out. Unparseable lines are ignored, as before the split.
    static func handle(line: String, env: Environment) -> String? {
        guard let data = line.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reply = handle(msg, env: env),
              let out = try? JSONSerialization.data(withJSONObject: reply) else { return nil }
        return String(data: out, encoding: .utf8)
    }

    /// The reply for one JSON-RPC message, or nil when none is owed (notifications, messages without an id).
    static func handle(_ msg: [String: Any], env: Environment) -> [String: Any]? {
        guard let method = msg["method"] as? String else { return nil }
        // Requests carry an id; notifications don't, and must never be answered.
        guard let id = msg["id"] else { return nil }
        func result(_ r: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": r] }
        func error(_ code: Int, _ message: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
        }
        let params = msg["params"] as? [String: Any]
        switch method {
        case "initialize":
            let requested = params?["protocolVersion"] as? String ?? "2025-06-18"
            return result(["protocolVersion": requested, "capabilities": ["tools": [String: Any]()],
                           "serverInfo": ["name": "reset", "version": "0.3.12"]])
        case "tools/list":
            return result(["tools": tools])
        case "tools/call":
            let args = params?["arguments"] as? [String: Any] ?? [:]
            switch params?["name"] as? String {
            case "get_claude_usage":
                let budget = Budget.load(from: env.budgetURL)
                return result(content(usageReport(snapshot: env.snapshot(), budget: budget, now: env.now())))
            case "set_budget":
                return result(content(setBudget(args, env: env)))
            case "clear_budget":
                let had = Budget.load(from: env.budgetURL)
                Budget.clear(at: env.budgetURL)
                return result(content(["cleared": had != nil, "task": had?.task ?? NSNull()]))
            default:
                return error(-32602, "Unknown tool")
            }
        case "ping":
            return result([:])
        default:
            // A notification sent with an id by mistake still isn't a request; stay silent as before.
            if method.hasPrefix("notifications/") { return nil }
            return error(-32601, "Method not found")
        }
    }

    /// A tool result: the report as pretty JSON text, flagged as an error when it carries one.
    private static func content(_ r: [String: Any]) -> [String: Any] {
        let text = (try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return ["content": [["type": "text", "text": text]], "isError": r["error"] != nil]
    }

    static let tools: [[String: Any]] = [
        [
            "name": "get_claude_usage",
            "description": "How much of the Claude usage window is left, when it resets, whether it will run out first at the current pace, today's API-value spend, and the active pacing budget if one is set. Use it before starting large or parallel work, and between steps while a budget is set.",
            "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
        ],
        [
            "name": "set_budget",
            "description": "Set a pacing budget for a task: the window usage percentage (absolute, as get_claude_usage reports it) at which to stop or downshift. get_claude_usage then advises normal, wrap_up from 80% of the cap, and over at the cap. Replaces any existing budget. It stays until clear_budget, also across window resets.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "task": ["type": "string", "description": "Short name of the task the budget is for."],
                    "max_window_percent": ["type": "integer", "minimum": 1, "maximum": 100,
                                           "description": "Window used % at which the task is over budget."],
                    "downshift_model": ["type": "string", "description": "Optional model to switch to once over budget, for example haiku."],
                ],
                "required": ["task", "max_window_percent"],
                "additionalProperties": false,
            ],
        ],
        [
            "name": "clear_budget",
            "description": "Remove the active pacing budget, for example when the task is done.",
            "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
        ],
    ]

    private static func setBudget(_ args: [String: Any], env: Environment) -> [String: Any] {
        let (budget, problem) = Budget.from(arguments: args, now: env.now())
        guard let budget else { return ["error": problem ?? "invalid arguments"] }
        do { try budget.save(to: env.budgetURL) } catch {
            return ["error": "Couldn't save the budget: \(error.localizedDescription)"]
        }
        let used = env.snapshot().flatMap { usedPercent($0, now: env.now()) }
        return ["budget": budgetReport(budget, used: used)]
    }

    // MARK: Report

    private static let iso = ISO8601DateFormatter()
    private static let local: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f }()

    /// Money as an exact two-decimal JSON number, without binary float noise.
    static func usd(_ v: Double) -> NSDecimalNumber { NSDecimalNumber(string: String(format: "%.2f", v)) }

    /// The window's used percentage, 0 when a fresh window is ready, nil when unknown.
    static func usedPercent(_ snap: WidgetSnapshot, now: Date) -> Double? {
        guard let c = snap.claude else { return nil }
        let ready = c.ready || (c.resetsAt.map { $0 <= now } ?? false)
        return ready ? 0 : c.used
    }

    static func budgetReport(_ b: Budget, used: Double?) -> [String: Any] {
        var out: [String: Any] = [
            "task": b.task, "max_window_percent": b.maxPercent, "set_at": iso.string(from: b.setAt),
            "status": b.status(used: used).rawValue, "advice": b.advice(used: used),
        ]
        if let m = b.downshiftModel { out["downshift_model"] = m }
        return out
    }

    static func usageReport(snapshot: WidgetSnapshot?, budget: Budget?, now: Date) -> [String: Any] {
        guard let snap = snapshot else {
            var out: [String: Any] = ["error": "Reset isn't running or hasn't written usage yet. Open Reset.app."]
            // The budget is still worth reporting: it lives in its own file and stays true without the app.
            if let budget { out["budget"] = budgetReport(budget, used: nil) }
            return out
        }
        var out: [String: Any] = ["updated": iso.string(from: snap.updated)]
        let used = usedPercent(snap, now: now)
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
            // An agent pacing itself should know when these numbers are a guess, and why.
            claude["estimated"] = c.estimate != nil
            if let e = c.estimate { claude["estimate_note"] = e }
            if let o = snap.claudeRunsOutAt, o > now {
                claude["projected_run_out_local"] = local.string(from: o)
                claude["minutes_until_run_out"] = Int(o.timeIntervalSince(now) / 60)
            }
            out["claude"] = claude
            // Plain-language advice an agent can act on.
            let left = ready ? 100.0 : (c.used.map { 100 - $0 } ?? 100)
            let budgetStatus = budget?.status(used: used)
            if let b = c.blockedUntil, b > now {
                // Nothing can run at all, so this outranks any budget.
                out["advice"] = "The weekly limit is exhausted until \(local.string(from: b)). Pause non-essential work."
            } else if let budget, budgetStatus == .over {
                // Over budget is the most specific instruction there is: it names the task and the model to switch to.
                out["advice"] = budget.advice(used: used)
            } else if snap.claudeRunsOutAt != nil || left < 15 {
                out["advice"] = "Window nearly exhausted. Finish the current step, prefer smaller models for subagents, avoid broad fan-outs until the reset."
            } else if let budget, budgetStatus == .wrapUp {
                out["advice"] = budget.advice(used: used)
            } else if left < 50 {
                out["advice"] = "Under half the window left. Keep subagents lean and batch tool calls."
            } else {
                out["advice"] = "Plenty of window left."
            }
        }
        if let budget { out["budget"] = budgetReport(budget, used: used) }
        var cost: [String: Any] = ["last_7_days_usd": usd(snap.weekCost)]
        if let t = snap.todayCumulative?.last { cost["today_usd"] = usd(t) }
        if let m = snap.monthCost { cost["last_30_days_usd"] = usd(m) }
        cost["note"] = "API list-price value of Claude Code usage, not a bill."
        out["cost"] = cost
        return out
    }
}
