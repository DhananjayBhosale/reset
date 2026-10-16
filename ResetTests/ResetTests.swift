import XCTest
@testable import Reset

/// The numbers people quote: what a response costs, that each response is counted once,
/// when a window resets, and when it will run out.
final class PricingTests: XCTestCase {
    func testOpus55List() {
        let p = Pricing.claude("claude-opus-5-5")!
        // 1M of each: 4 + 5 + 8 + 0.2 + 20
        XCTAssertEqual(Pricing.cost(p, input: 1_000_000, cw5: 1_000_000, cw1h: 1_000_000, cacheRead: 1_000_000, output: 1_000_000), 37.2, accuracy: 1e-9)
    }

    func testSonnet55CacheReadIsTenCents() {
        XCTAssertEqual(Pricing.claude("claude-sonnet-5-5")!.cacheRead, 0.10)
    }

    func testHaiku55SwitchesWholeRequestAbove100k() {
        let p = Pricing.claude("claude-haiku-5-5")!
        let small = Pricing.cost(p, input: 50_000, cw5: 0, cw1h: 0, cacheRead: 40_000, output: 1_000)
        XCTAssertEqual(small, (50_000 * 0.1 + 40_000 * 0.01 + 1_000 * 0.5) / 1_000_000, accuracy: 1e-12)
        let big = Pricing.cost(p, input: 50_000, cw5: 0, cw1h: 0, cacheRead: 60_000, output: 1_000)
        XCTAssertEqual(big, (50_000 * 0.5 + 60_000 * 0.05 + 1_000 * 2.5) / 1_000_000, accuracy: 1e-12)
    }

    func testOneMillionContextSuffixPricesLikeBase() {
        XCTAssertEqual(Pricing.claude("claude-opus-5[1m]")?.input, Pricing.claude("claude-opus-5")?.input)
    }

    func testUnknownModelIsUnpriced() {
        XCTAssertNil(Pricing.claude("gpt-5.5"))
    }
}

final class TranscriptTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func row(_ id: String, out: Int, time: String = "2026-10-14T10:00:00.000Z", req: String = "req_1",
                     content: String = #"[{"type":"text","text":"hi"}]"#, extra: String = "") -> String {
        #"{"type":"assistant","timestamp":"\#(time)","sessionId":"s1","cwd":"/tmp/p","requestId":"\#(req)","message":{"id":"\#(id)","model":"claude-opus-5-5","content":\#(content),"usage":{"input_tokens":10,"cache_read_input_tokens":1000,"output_tokens":\#(out),"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":100}\#(extra)}}}"#
    }

    private func write(_ name: String, _ lines: [String]) -> URL {
        let u = dir.appendingPathComponent(name)
        try! (lines.joined(separator: "\n") + "\n").write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    private func parse(_ u: URL) -> ClaudeUsageScanner.FileResult {
        let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ClaudeUsageScanner.parse(u, mtime: Date(), size: size, from: 0)
    }

    func testStreamedRowsCountOnceWithFinalOutput() {
        // Claude Code writes one row per content block; early rows carry a placeholder output count.
        let u = write("a.jsonl", [row("m1", out: 3), row("m1", out: 3), row("m1", out: 640)])
        let r = parse(u)
        XCTAssertEqual(r.calls.count, 1)
        XCTAssertEqual(r.calls.first?.output, 640)
    }

    func testResumedCopyInAnotherFileIsNotDoubleCounted() {
        let a = parse(write("a.jsonl", [row("m1", out: 640)]))
        let b = parse(write("b.jsonl", [row("m1", out: 640, time: "2026-10-14T12:00:00.000Z"), row("m2", out: 50)]))
        let r = ClaudeUsageScanner.combine([a, b], since: .distantPast)
        XCTAssertEqual(r.calls.count, 2)
        XCTAssertEqual(r.calls.first { $0.id == "m1" }?.time, ISO8601DateFormatter().date(from: "2026-10-14T10:00:00Z"))
    }

    func testErrorAndSyntheticRowsAreSkipped() {
        let err = #"{"type":"assistant","isApiErrorMessage":true,"timestamp":"2026-10-14T10:00:00.000Z","message":{"id":"e1","model":"claude-opus-5-5","usage":{"output_tokens":5}}}"#
        let syn = #"{"type":"assistant","timestamp":"2026-10-14T10:00:00.000Z","message":{"id":"y1","model":"<synthetic>","usage":{"output_tokens":0}}}"#
        XCTAssertEqual(parse(write("a.jsonl", [err, syn])).calls.count, 0)
    }

    func testLimitRowIsRecordedNotBilled() {
        let hit = #"{"type":"assistant","timestamp":"2026-10-14T10:00:00.000Z","isApiErrorMessage":true,"quotaLimits":{"status":"rejected","resetsAt":1791734400,"rateLimitType":"five_hour"},"message":{"id":"x","model":"<synthetic>"}}"#
        let r = parse(write("a.jsonl", [hit]))
        XCTAssertEqual(r.calls.count, 0)
        XCTAssertEqual(r.limitHits.count, 1)
    }

    func testAdvisorTokensArePricedWithTheirModel() {
        let extra = #","iterations":[{"type":"message","input_tokens":10,"output_tokens":100},{"type":"advisor_message","model":"claude-opus-5","input_tokens":1000,"output_tokens":200}]"#
        let r = parse(write("a.jsonl", [row("m1", out: 100, extra: extra)]))
        let opus5 = Pricing.claude("claude-opus-5")!
        let advisor = Pricing.cost(opus5, input: 1000, cw5: 0, cw1h: 0, cacheRead: 0, output: 200)
        let main = Pricing.cost(Pricing.claude("claude-opus-5-5")!, input: 10, cw5: 0, cw1h: 100, cacheRead: 1000, output: 100)
        XCTAssertEqual(r.calls.first!.cost, main + advisor, accuracy: 1e-12)
        XCTAssertEqual(r.calls.first!.advisorTokens, 1200)
    }

    func testMCPCallsAreCountedPerServer() {
        let content = #"[{"type":"tool_use","name":"mcp__github__create_issue"},{"type":"tool_use","name":"Read"}]"#
        let r = parse(write("a.jsonl", [row("m1", out: 10, content: content)]))
        XCTAssertEqual(r.calls.first?.tools, 2)
        XCTAssertEqual(r.calls.first?.mcpServers, ["github": 1])
    }

    func testIncrementalParseMatchesFullParse() {
        let lines = (0..<40).map { row("m\($0 / 3)", out: $0 % 3 == 2 ? 500 + $0 : 3) }
        let u = write("a.jsonl", lines)
        let full = parse(u)
        let data = try! Data(contentsOf: u)
        let mid = data[..<(data.count / 2)].lastIndex(of: UInt8(ascii: "\n"))! + 1
        var first = ClaudeUsageScanner.parse(u, mtime: Date(), size: mid, from: 0)
        first.offset = mid
        let merged = ClaudeUsageScanner.merge(first, ClaudeUsageScanner.parse(u, mtime: Date(), size: data.count, from: mid))
        XCTAssertEqual(merged.calls.count, full.calls.count)
        XCTAssertEqual(merged.calls.reduce(0) { $0 + $1.output }, full.calls.reduce(0) { $0 + $1.output })
        XCTAssertEqual(merged.calls.reduce(0) { $0 + $1.cost }, full.calls.reduce(0) { $0 + $1.cost }, accuracy: 1e-12)
    }

    func testMergingAFullReparseDoesNotInflateToolCounts() {
        // An unchanged file re-parsed in full and merged into its cached result must leave counts alone.
        let tools = #"[{"type":"tool_use","name":"mcp__github__create_issue"},{"type":"tool_use","name":"Read"}]"#
        let u = write("a.jsonl", [row("m1", out: 3, content: tools), row("m1", out: 640), row("m2", out: 90, content: tools)])
        let cached = parse(u)
        let again = ClaudeUsageScanner.merge(cached, parse(u))
        XCTAssertEqual(again.calls.reduce(0) { $0 + $1.tools }, cached.calls.reduce(0) { $0 + $1.tools })
        XCTAssertEqual(again.calls.reduce(0) { $0 + $1.mcpCalls }, cached.calls.reduce(0) { $0 + $1.mcpCalls })
        XCTAssertEqual(again.calls.reduce(0) { $0 + $1.cost }, cached.calls.reduce(0) { $0 + $1.cost }, accuracy: 1e-12)
        XCTAssertEqual(again.calls.reduce(0) { $0 + $1.output }, cached.calls.reduce(0) { $0 + $1.output })
    }

    func testHalfWrittenLastLineWaitsForNextScan() {
        let u = dir.appendingPathComponent("a.jsonl")
        try! (row("m1", out: 10) + "\n" + #"{"type":"assistant","timestam"#).write(to: u, atomically: true, encoding: .utf8)
        let r = parse(u)
        XCTAssertEqual(r.calls.count, 1)
        XCTAssertEqual(r.offset, row("m1", out: 10).utf8.count + 1)
    }
}

final class WindowTests: XCTestCase {
    private func d(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testWindowStartsAtFirstMessageFlooredToTenMinutes() {
        let a = d("2026-10-14T06:47:30Z")
        let r = ClaudeSource.compute(events: [.init(time: a, kind: .activity)], activity: [a], now: d("2026-10-14T07:00:00Z"))
        XCTAssertEqual(r.window?.end, d("2026-10-14T11:40:00Z"))
        XCTAssertEqual(r.window?.exact, false)
    }

    func testNextWindowChainsFromFirstMessageAfterReset() {
        let s = [d("2026-10-14T06:47:30Z"), d("2026-10-14T09:00:00Z"), d("2026-10-14T11:52:00Z")]
        let r = ClaudeSource.compute(events: s.map { .init(time: $0, kind: .activity) }, activity: s, now: d("2026-10-14T12:00:00Z"))
        XCTAssertEqual(r.window?.end, d("2026-10-14T16:50:00Z"))
    }

    func testWindowEndsAndIsReady() {
        let a = d("2026-10-14T06:47:30Z")
        let r = ClaudeSource.compute(events: [.init(time: a, kind: .activity)], activity: [a], now: d("2026-10-14T12:00:00Z"))
        XCTAssertNil(r.window)
    }

    func testExactLimitRowOverridesEstimate() {
        let a = d("2026-10-14T06:47:30Z"), hit = d("2026-10-14T09:00:00Z"), reset = d("2026-10-14T11:30:00Z")
        let r = ClaudeSource.compute(events: [.init(time: a, kind: .activity), .init(time: hit, kind: .fiveHourLimit(reset))],
                                     activity: [a], now: d("2026-10-14T10:00:00Z"))
        XCTAssertEqual(r.window?.end, reset)
        XCTAssertEqual(r.window?.exact, true)
    }

    func testLimitRowIgnoredWhenWorkContinuedOnAnotherAccount() {
        let a = d("2026-10-14T06:47:30Z"), hit = d("2026-10-14T09:00:00Z"), later = d("2026-10-14T09:30:00Z")
        let r = ClaudeSource.compute(events: [.init(time: a, kind: .activity), .init(time: hit, kind: .fiveHourLimit(d("2026-10-14T11:30:00Z"))),
                                              .init(time: later, kind: .activity)],
                                     activity: [a, later], now: d("2026-10-14T10:00:00Z"))
        XCTAssertEqual(r.window?.exact, false)
        XCTAssertEqual(r.window?.end, d("2026-10-14T11:40:00Z"))
    }

    func testWeeklyLimitBlocks() {
        let hit = d("2026-10-14T09:00:00Z"), until = d("2026-10-16T05:00:00Z")
        let r = ClaudeSource.compute(events: [.init(time: hit, kind: .weeklyLimit(until))], activity: [], now: d("2026-10-14T10:00:00Z"))
        XCTAssertEqual(r.weeklyBlockUntil, until)
    }
}

final class ForecastTests: XCTestCase {
    func testWarnsOnceWhenPaceRunsOutBeforeReset() {
        let f = Forecast(), start = Date(), reset = start.addingTimeInterval(7200)
        for m in 0...15 { f.record(used: 40 + Double(m), resetsAt: reset, now: start.addingTimeInterval(Double(m) * 60)) }
        let now = start.addingTimeInterval(15 * 60)
        XCTAssertEqual(f.runsOutAt!.timeIntervalSince(now) / 60, 45, accuracy: 1)
        XCTAssertTrue(f.shouldWarn())
        XCTAssertFalse(f.shouldWarn())
    }

    func testNoWarningWhenPaceIsFine() {
        let f = Forecast(), start = Date(), reset = start.addingTimeInterval(7200)
        for m in 0...15 { f.record(used: 40 + Double(m) * 0.1, resetsAt: reset, now: start.addingTimeInterval(Double(m) * 60)) }
        XCTAssertNil(f.runsOutAt)
    }

    func testNewWindowStartsFresh() {
        let f = Forecast(), start = Date()
        for m in 0...15 { f.record(used: 40 + Double(m), resetsAt: start.addingTimeInterval(7200), now: start.addingTimeInterval(Double(m) * 60)) }
        f.record(used: 1, resetsAt: start.addingTimeInterval(30000), now: start.addingTimeInterval(16 * 60))
        XCTAssertNil(f.runsOutAt)
    }
}

final class ProjectAndVersionTests: XCTestCase {
    private let home = NSHomeDirectory()

    func testSubfoldersFoldIntoProjectRoot() {
        XCTAssertEqual(ProjectNames.root(of: "\(home)/Desktop/My Video/Edit/tools"), "\(home)/Desktop/My Video")
        XCTAssertEqual(ProjectNames.root(of: "\(home)/Developer/app/src/main/java"), "\(home)/Developer/app")
    }

    func testWorktreesFoldIntoTheirRepo() {
        XCTAssertEqual(ProjectNames.root(of: "\(home)/Desktop/api/.claude/worktrees/fix-auth/backend"), "\(home)/Desktop/api")
    }

    func testIDEWorkspaceFolders() {
        XCTAssertEqual(ProjectNames.root(of: "\(home)/Documents/antigravity/brave-heisenberg"), "\(home)/Documents/antigravity/brave-heisenberg")
    }

    func testCleanedNames() {
        XCTAssertEqual(ProjectNames.cleaned("\(home)/Desktop/1. Launch Video FINAL"), "Launch Video FINAL")
        XCTAssertEqual(ProjectNames.cleaned("\(home)/Developer/torlink-app_v2"), "torlink app v2")
        XCTAssertEqual(ProjectNames.cleaned(home), "Home folder")
    }

    func testVersionComparison() {
        XCTAssertTrue(Updater.isNewer("0.2", than: "0.1"))
        XCTAssertTrue(Updater.isNewer("0.10", than: "0.9"))
        XCTAssertFalse(Updater.isNewer("0.1", than: "0.1"))
        XCTAssertFalse(Updater.isNewer("0.1", than: "0.1.1"))
        XCTAssertTrue(Updater.isNewer("1.0", than: "0.99"))
    }
}


final class MonthBucketTests: XCTestCase {
    private func call(_ t: Date, cost: Double) -> Call {
        Call(id: UUID().uuidString, time: t, model: "claude-opus-5-5", session: "s", project: "/tmp/p", sidechain: false,
             input: 0, cw5: 0, cw1h: 0, cacheRead: 0, output: 0, advisorTokens: 0, tools: 0, mcpServers: [:],
             webSearches: 0, mcpAttribution: nil, cost: cost, autoStart: false)
    }

    func testFutureDatedRowsAreSkippedNotCrashing() {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let days = cal.range(of: .day, in: .month, for: monthStart)!.count
        let calls = [call(monthStart.addingTimeInterval(3600), cost: 2),
                     call(monthStart.addingTimeInterval(86400 * 1.5), cost: 3),
                     call(monthStart.addingTimeInterval(86400 * 62), cost: 99),   // about two months ahead
                     call(monthStart.addingTimeInterval(-86400), cost: 50)]       // last month
        let b = Store.monthBuckets(calls, monthStart: monthStart, daysInMonth: days, calendar: cal)
        XCTAssertEqual(b.count, days)
        XCTAssertEqual(b[0], 2)
        XCTAssertEqual(b[1], 3)
        XCTAssertEqual(b.reduce(0, +), 5)
    }
}

/// The forecast survives a restart: same projection afterwards, and no second warning for the same window.
final class ForecastPersistenceTests: XCTestCase {
    private var url: URL!
    override func setUp() { url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-forecast.json") }
    override func tearDown() { try? FileManager.default.removeItem(at: url) }

    func testProjectionAndWarningSurviveARestart() {
        let start = Date(timeIntervalSince1970: 1_772_442_000), reset = start.addingTimeInterval(7200)
        let before = Forecast(storeURL: url, now: start)
        for m in 0...15 { before.record(used: 40 + Double(m), resetsAt: reset, now: start.addingTimeInterval(Double(m) * 60)) }
        XCTAssertNotNil(before.runsOutAt)
        XCTAssertTrue(before.shouldWarn())
        // Reset quits and starts again two minutes later.
        let after = Forecast(storeURL: url, now: start.addingTimeInterval(17 * 60))
        XCTAssertNotNil(after.runsOutAt, "the run-out warning is there straight away")
        XCTAssertEqual(after.runsOutAt!.timeIntervalSince1970, before.runsOutAt!.timeIntervalSince1970, accuracy: 120)
        XCTAssertFalse(after.shouldWarn(), "already warned for this window, so no second notification or push")
    }

    func testAnEndedWindowIsDropped() {
        let start = Date(timeIntervalSince1970: 1_772_442_000), reset = start.addingTimeInterval(1800)
        let before = Forecast(storeURL: url, now: start)
        for m in 0...15 { before.record(used: 40 + Double(m), resetsAt: reset, now: start.addingTimeInterval(Double(m) * 60)) }
        let after = Forecast(storeURL: url, now: reset.addingTimeInterval(60))
        XCTAssertNil(after.runsOutAt)
        XCTAssertTrue(after.readings.isEmpty)
    }

    func testOldReadingsAreDroppedOnLoad() {
        let start = Date(timeIntervalSince1970: 1_772_442_000), reset = start.addingTimeInterval(5 * 3600)
        let before = Forecast(storeURL: url, now: start)
        for m in 0...15 { before.record(used: 40 + Double(m), resetsAt: reset, now: start.addingTimeInterval(Double(m) * 60)) }
        // An hour later every reading is older than the 45-minute span the projection uses.
        let after = Forecast(storeURL: url, now: start.addingTimeInterval(75 * 60))
        XCTAssertTrue(after.readings.isEmpty)
        XCTAssertNil(after.runsOutAt, "nothing stale is projected")
    }

    func testWithoutAStoreNothingIsWritten() {
        let f = Forecast()
        f.record(used: 10, resetsAt: Date().addingTimeInterval(3600))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

/// Live usage is fetched often while Claude Code is in use and rarely when it isn't.
final class LivePollTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_772_442_000)

    func testActiveUseFetchesAboutEveryMinute() {
        XCTAssertEqual(LiveClaude.interval(lastActivity: now.addingTimeInterval(-30), now: now), 55)
        XCTAssertEqual(LiveClaude.interval(lastActivity: now.addingTimeInterval(-299), now: now), 55)
        XCTAssertLessThan(LiveClaude.activeInterval, 60, "the app refreshes every 60 s; exactly 60 would sometimes wait two")
    }

    func testIdleFetchesEveryFiveMinutes() {
        XCTAssertEqual(LiveClaude.interval(lastActivity: now.addingTimeInterval(-301), now: now), 300)
        XCTAssertEqual(LiveClaude.interval(lastActivity: nil, now: now), 300, "no activity seen at all")
    }
}
