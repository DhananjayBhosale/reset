import XCTest
@testable import Reset

/// Format-drift check: re-parses the anonymised samples in Fixtures/transcripts with the real parsers and
/// compares the result with the golden JSON in Fixtures/golden. A difference means parser behaviour changed;
/// see "When the drift check fails" in the README.
///
/// scripts/drift-check.sh runs only this class. `--update-goldens` (environment RESET_UPDATE_GOLDENS=1 in the
/// test process) rewrites the goldens instead of comparing. The actual output always lands in
/// build/drift/actual, so a failure can be read with `diff -u`.
final class DriftTests: XCTestCase {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private let transcripts = repo.appendingPathComponent("Fixtures/transcripts")
    private let golden = repo.appendingPathComponent("Fixtures/golden")
    private let actual = repo.appendingPathComponent("build/drift/actual")
    private var updating: Bool { ProcessInfo.processInfo.environment["RESET_UPDATE_GOLDENS"] == "1" }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private func date(_ s: String) -> Date { Self.iso.date(from: s)! }

    // MARK: Claude Code transcripts, usage parser

    func testClaudeStreamedSession() throws {
        let r = parse("claude/streamed.jsonl")
        // Sanity beyond the golden, so a regenerated golden can't quietly become empty.
        XCTAssertEqual(r.calls.count, 3, "streamed rows, a sidechain call, and skipped synthetic/error rows")
        XCTAssertEqual(r.calls.first { $0.id == "msg_fixture_stream_A" }?.output, 380)
        XCTAssertEqual(r.titles.count, 1)
        try check("claude-usage/streamed.json", render(r))
    }

    func testClaudeQuotaLimitRows() throws {
        let r = parse("claude/quota.jsonl")
        XCTAssertEqual(r.limitHits.count, 1, "only five_hour rows are limit hits for the usage parser")
        XCTAssertEqual(r.calls.count, 2)
        try check("claude-usage/quota.json", render(r))
    }

    func testClaudeResumedSessionDeduplicates() throws {
        let combined = ClaudeUsageScanner.combine([parse("claude/resumed/original.jsonl"), parse("claude/resumed/resumed.jsonl")],
                                                  since: .distantPast)
        XCTAssertEqual(combined.calls.count, 3, "copied rows count once")
        try check("claude-usage/resumed-combined.json", [
            "calls": render(combined.calls), "titles": combined.titles,
            "limitHits": combined.limitHits.map(Self.iso.string), "apiMillis": combined.apiMillis,
        ])
    }

    // MARK: Claude Code transcripts, window events and chain

    func testClaudeWindowEventsAndChain() throws {
        var out: [String: Any] = [:]
        for name in ["streamed", "quota"] {
            let u = transcripts.appendingPathComponent("claude/\(name).jsonl")
            let (events, offset) = TranscriptScanner.parse(u, from: 0, size: size(u))
            out["\(name).events"] = events.map(render)
            out["\(name).offset"] = offset
        }
        let u = transcripts.appendingPathComponent("claude/quota.jsonl")
        let events = TranscriptScanner.parse(u, from: 0, size: size(u)).0
        XCTAssertEqual(events.filter { if case .fiveHourLimit = $0.kind { return true }; return false }.count, 1)
        XCTAssertEqual(events.filter { if case .weeklyLimit = $0.kind { return true }; return false }.count, 1)
        let activity = events.filter { $0.kind == .activity }.map(\.time)
        // Inside the exact window, then after it with the weekly block in force.
        for now in ["2026-03-03T16:45:00.000Z", "2026-03-03T17:15:00.000Z"] {
            let c = ClaudeSource.compute(events: events, activity: activity, now: date(now))
            out["quota.window@\(now)"] = [
                "end": c.window.map { Self.iso.string(from: $0.end) as Any } ?? NSNull(),
                "exact": c.window.map { $0.exact as Any } ?? NSNull(),
                "weeklyBlockUntil": c.weeklyBlockUntil.map { Self.iso.string(from: $0) as Any } ?? NSNull(),
            ]
        }
        try check("claude-window/events.json", out)
    }

    // MARK: Codex and the Claude desktop app

    func testCodexRateLimits() throws {
        let s = CodexSource().read(now: date("2026-03-02T10:00:00.000Z"), root: transcripts.appendingPathComponent("codex"))
        XCTAssertNotNil(s.resetsAt, "integer window_minutes and resets_at must still parse")
        try check("codex/rollout.json", render(s))
    }

    func testPlanUsageHistory() throws {
        let u = transcripts.appendingPathComponent("claude-desktop/plan-usage-history.json")
        var out: [String: Any] = [:]
        for org in ["org-fixture-a", "org-fixture-b", "org-fixture-missing"] {
            out[org] = PlanUsageLog.latest(org: org, url: u).map { s -> [String: Any] in
                ["time": Self.iso.string(from: s.time), "fiveHour": s.fiveHour, "sevenDay": s.sevenDay ?? NSNull()]
            } ?? NSNull()
        }
        XCTAssertEqual(PlanUsageLog.latest(org: "org-fixture-a", url: u)?.fiveHour, 41.5)
        try check("claude-desktop/plan-usage.json", out)
    }

    // MARK: Rendering

    private func size(_ u: URL) -> Int { (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }

    /// A fixed mtime keeps the golden independent of when the fixture was checked out.
    private func parse(_ rel: String) -> ClaudeUsageScanner.FileResult {
        let u = transcripts.appendingPathComponent(rel)
        return ClaudeUsageScanner.parse(u, mtime: Date(timeIntervalSince1970: 0), size: size(u), from: 0)
    }

    /// Money with float noise cut off, as a JSON number.
    private func money(_ v: Double) -> NSDecimalNumber { NSDecimalNumber(string: String(format: "%.8f", v)) }

    private func render(_ r: ClaudeUsageScanner.FileResult) -> [String: Any] {
        ["calls": render(r.calls), "titles": r.titles, "limitHits": r.limitHits.map(Self.iso.string),
         "apiMillis": r.apiMillis, "offset": r.offset, "size": r.size]
    }

    /// Sorted by time then id: the parsers return dictionary values, whose order isn't stable.
    private func render(_ calls: [Call]) -> [[String: Any]] {
        calls.sorted { ($0.time, $0.id) < ($1.time, $1.id) }.map { c in
            ["id": c.id, "time": Self.iso.string(from: c.time), "model": c.model, "session": c.session, "project": c.project,
             "sidechain": c.sidechain, "input": c.input, "cw5": c.cw5, "cw1h": c.cw1h, "cacheRead": c.cacheRead,
             "output": c.output, "advisorTokens": c.advisorTokens, "tools": c.tools, "mcpServers": c.mcpServers,
             "webSearches": c.webSearches, "mcpAttribution": c.mcpAttribution ?? NSNull(), "cost": money(c.cost),
             "autoStart": c.autoStart]
        }
    }

    private func render(_ e: TranscriptScanner.Event) -> [String: Any] {
        switch e.kind {
        case .activity: return ["time": Self.iso.string(from: e.time), "kind": "activity"]
        case .fiveHourLimit(let r): return ["time": Self.iso.string(from: e.time), "kind": "fiveHourLimit", "resetsAt": Self.iso.string(from: r)]
        case .weeklyLimit(let r): return ["time": Self.iso.string(from: e.time), "kind": "weeklyLimit", "resetsAt": Self.iso.string(from: r)]
        }
    }

    private func render(_ s: WindowStatus) -> [String: Any] {
        let state: Any
        switch s.state {
        case .active(let r): state = ["active": Self.iso.string(from: r)]
        case .ready: state = "ready"
        case .unavailable(let why): state = ["unavailable": why]
        }
        return ["state": state, "usedPercent": s.usedPercent ?? NSNull(), "isEstimate": s.isEstimate, "source": s.source,
                "blockedUntil": s.blockedUntil.map(Self.iso.string) ?? NSNull(),
                "secondary": s.secondary.map { ["label": $0.label, "resetsAt": Self.iso.string(from: $0.resetsAt),
                                                "usedPercent": $0.usedPercent ?? NSNull()] as [String: Any] } ?? NSNull()]
    }

    // MARK: Compare or update

    private func check(_ rel: String, _ value: Any, file: StaticString = #filePath, line: UInt = #line) throws {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(UInt8(ascii: "\n"))
        let fm = FileManager.default
        let a = actual.appendingPathComponent(rel)
        try fm.createDirectory(at: a.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: a, options: .atomic)
        let g = golden.appendingPathComponent(rel)
        if updating {
            try fm.createDirectory(at: g.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: g, options: .atomic)
            return
        }
        guard let expected = try? Data(contentsOf: g) else {
            XCTFail("No golden at Fixtures/golden/\(rel). Run ./scripts/drift-check.sh --update-goldens.", file: file, line: line)
            return
        }
        guard expected != data else { return }
        // Point at the first differing line; the full picture is `diff -u` between golden and actual.
        let e = String(decoding: expected, as: UTF8.self).components(separatedBy: "\n")
        let n = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        let i = zip(e, n).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(e.count, n.count)
        XCTFail("""
            Drift in Fixtures/golden/\(rel) at line \(i + 1):
              golden: \(i < e.count ? e[i] : "<end>")
              actual: \(i < n.count ? n[i] : "<end>")
            Full diff: diff -u Fixtures/golden/\(rel) build/drift/actual/\(rel)
            """, file: file, line: line)
    }
}
