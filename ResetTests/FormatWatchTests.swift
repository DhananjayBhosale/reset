import XCTest
@testable import Reset

/// The log-format watcher: rows that look like usage but can't be read are counted, and enough of them
/// recently turns into a warning in Settings.
final class FormatWatchTests: XCTestCase {
    private var dir: URL!
    /// The fixtures copied into the test bundle (see project.yml), so the repo's folder is never read.
    private static let fixtures = Bundle(for: FormatWatchTests.self).resourceURL!.appendingPathComponent("Fixtures")

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func parse(_ lines: [String]) -> ClaudeUsageScanner.FormatHealth {
        let u = dir.appendingPathComponent(UUID().uuidString + ".jsonl")
        try! (lines.joined(separator: "\n") + "\n").write(to: u, atomically: true, encoding: .utf8)
        let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ClaudeUsageScanner.parse(u, mtime: Date(), size: size, from: 0).health!
    }

    private let good = #"{"type":"assistant","version":"2.9.0","timestamp":"2026-03-02T09:14:05.120Z","sessionId":"s","requestId":"r","message":{"id":"m1","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":10,"output_tokens":20}}}"#

    // MARK: Parser

    func testRealFormatFixturesHaveNoProblems() {
        for name in ["streamed", "quota", "resumed/original", "resumed/resumed"] {
            let u = Self.fixtures.appendingPathComponent("transcripts/claude/\(name).jsonl")
            let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let h = ClaudeUsageScanner.parse(u, mtime: Date(), size: size, from: 0).health!
            XCTAssertEqual(h.problems, [:], name)
            XCTAssertGreaterThan(h.checked, 0, name)
        }
    }

    func testEachKindOfUnreadableRowIsCounted() {
        let rows = [
            good,
            #"{"type":"assistant","timestamp":"2026-03-02T09:14:05.120Z","message":{"id":"m2","#,                                       // cut off
            #"{"type":"assistant","timestamp":"2026-03-02T09:14:05Z","message":{"id":"m3","model":"claude-opus-5-5","usage":{"input_tokens":1,"output_tokens":1}}}"#,  // no fractional seconds
            #"{"type":"assistant","timestamp":"2026-03-02T09:14:05.120Z","response":{"id":"m4"}}"#,                                      // message renamed
            #"{"type":"assistant","timestamp":"2026-03-02T09:14:05.120Z","message":{"id":"m5","model":"claude-opus-5-5","tokens":{}}}"#,  // usage renamed
            #"{"type":"assistant","timestamp":"2026-03-02T09:14:05.120Z","message":{"id":"m6","model":"claude-opus-5-5","usage":{"input_tokens":"10","output_tokens":20}}}"#,
            #"{"type":"assistant","timestamp":"2026-03-02T09:14:05.120Z","isApiErrorMessage":true,"quotaLimits":{"status":"rejected","resetsAt":1772557800,"rateLimitType":"monthly"},"message":{"id":"x","model":"<synthetic>"}}"#,
        ]
        let h = parse(rows)
        XCTAssertEqual(h.checked, 7)
        XCTAssertEqual(h.problems, ["unreadable_row": 1, "no_timestamp": 1, "no_message": 1, "missing_fields": 1,
                                    "usage_shape": 1, "unknown_limit": 1])
        XCTAssertEqual(h.version, "2.9.0")
    }

    func testRowsThatAreSkippedOnPurposeAreNotProblems() {
        let rows = [
            #"{"type":"assistant","timestamp":"2026-03-02T09:14:05.120Z","message":{"id":"y","model":"<synthetic>","usage":{"output_tokens":0}}}"#,
            #"{"type":"assistant","timestamp":"2026-03-02T09:14:05.120Z","isApiErrorMessage":true,"message":{"id":"e","model":"claude-opus-5-5"}}"#,
            #"{"type":"assistant","timestamp":"2026-03-02T09:14:05.120Z","isApiErrorMessage":true,"quotaLimits":{"status":"rejected","resetsAt":1772557800,"rateLimitType":"seven_day"},"message":{"id":"x","model":"<synthetic>"}}"#,
            // A user row carrying an assistant-shaped object inside it: not a top-level assistant row.
            #"{"type":"user","timestamp":"2026-03-02T09:14:05.120Z","message":{"content":[{"inner":{"type":"assistant"}}]}}"#,
        ]
        let h = parse(rows)
        XCTAssertEqual(h.problems, [:])
        XCTAssertEqual(h.checked, 3)
        XCTAssertEqual(h.lines, 4)
    }

    func testUnreadableRowsDontChangeWhatIsCounted() {
        let cut = #"{"type":"assistant","timestamp":"2026-03-02T09:14:05.120Z","message":{"id":"m2","#
        let u = dir.appendingPathComponent("a.jsonl")
        try! ([good, cut].joined(separator: "\n") + "\n").write(to: u, atomically: true, encoding: .utf8)
        let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let r = ClaudeUsageScanner.parse(u, mtime: Date(), size: size, from: 0)
        XCTAssertEqual(r.calls.count, 1)
        XCTAssertEqual(r.calls.first?.output, 20)
    }

    func testIncrementalParseAddsUpHealth() {
        let u = dir.appendingPathComponent("a.jsonl")
        let bad = #"{"type":"assistant","timestamp":"2026-03-02T09:14:05Z","message":{}}"#
        try! ([good, bad, good, bad].joined(separator: "\n") + "\n").write(to: u, atomically: true, encoding: .utf8)
        let data = try! Data(contentsOf: u)
        let mid = (good + "\n" + bad + "\n").utf8.count
        let first = ClaudeUsageScanner.parse(u, mtime: Date(), size: mid, from: 0)
        let merged = ClaudeUsageScanner.merge(first, ClaudeUsageScanner.parse(u, mtime: Date(), size: data.count, from: mid))
        let full = ClaudeUsageScanner.parse(u, mtime: Date(), size: data.count, from: 0)
        XCTAssertEqual(merged.health, full.health)
        XCTAssertEqual(full.health?.problems, ["no_timestamp": 2])
    }

    func testCacheWrittenBeforeTheWatcherStillDecodes() throws {
        let old = #"{"mtime":0,"size":10,"calls":[],"titles":{},"limitHits":[],"apiMillis":{},"offset":10}"#
        let r = try JSONDecoder().decode(ClaudeUsageScanner.FileResult.self, from: Data(old.utf8))
        XCTAssertNil(r.health)
        XCTAssertEqual(r.offset, 10)
    }

    // MARK: Verdict

    private let now = Date(timeIntervalSince1970: 1_772_442_000)

    private func file(age: TimeInterval = 3600, lines: Int, checked: Int, problems: [String: Int] = [:],
                      version: String? = nil) -> ClaudeUsageScanner.FileResult {
        ClaudeUsageScanner.FileResult(mtime: now.addingTimeInterval(-age), size: 0, calls: [], titles: [:], limitHits: [],
                                      apiMillis: [:], offset: 0,
                                      health: .init(lines: lines, checked: checked, problems: problems, version: version))
    }

    private func verdict(_ files: [ClaudeUsageScanner.FileResult]) -> ClaudeUsageScanner.FormatReport {
        ClaudeUsageScanner.formatReport(files, recentSince: now.addingTimeInterval(-ClaudeUsageScanner.recentWindow))
    }

    func testHealthyLogsAreOK() {
        let r = verdict([file(lines: 4000, checked: 1000)])
        XCTAssertEqual(r.verdict, .ok)
        XCTAssertTrue(r.summary.contains("1000 responses"))
    }

    func testTooLittleActivitySaysNothing() {
        XCTAssertEqual(verdict([file(lines: 150, checked: 0)]).verdict, .tooQuiet)
        XCTAssertEqual(verdict([]).verdict, .tooQuiet)
    }

    func testProblemsNeedBothACountAndAShare() {
        XCTAssertEqual(verdict([file(lines: 400, checked: 100, problems: ["no_timestamp": 3])]).verdict, .problems)
        XCTAssertEqual(verdict([file(lines: 400, checked: 100, problems: ["no_timestamp": 2])]).verdict, .ok, "two stray rows")
        XCTAssertEqual(verdict([file(lines: 9000, checked: 1000, problems: ["no_timestamp": 3])]).verdict, .ok, "3 of 1000 is noise")
        XCTAssertEqual(verdict([file(lines: 9000, checked: 1000, problems: ["no_timestamp": 25])]).verdict, .problems)
    }

    func testAFormatChangeThatHidesEveryRowIsCaught() {
        let r = verdict([file(lines: 600, checked: 0, version: "3.0.0")])
        XCTAssertEqual(r.verdict, .noRows)
        XCTAssertTrue(r.summary.contains("found no usage"))
    }

    func testOnlyRecentFilesCountAndTheNewestVersionIsNamed() {
        let r = verdict([
            file(age: 5 * 86400, lines: 9000, checked: 3000, version: "2.8.0"),    // old and healthy: ignored
            file(age: 7200, lines: 300, checked: 40, problems: ["usage_shape": 40], version: "2.9.0"),
            file(age: 600, lines: 100, checked: 20, problems: ["usage_shape": 20], version: "3.0.0"),
        ])
        XCTAssertEqual(r.verdict, .problems)
        XCTAssertEqual(r.checked, 60)
        XCTAssertEqual(r.version, "3.0.0")
        XCTAssertTrue(r.summary.contains("token counts in an unexpected shape"))
        XCTAssertTrue(r.summary.contains("Claude Code 3.0.0"))
    }

    func testSimulatedWarningsMatchTheRealOnes() {
        XCTAssertNil(UsageStore.simulatedFormat(nil))
        XCTAssertNil(UsageStore.simulatedFormat("something else"))
        XCTAssertEqual(UsageStore.simulatedFormat("problems")?.verdict, .problems)
        XCTAssertEqual(UsageStore.simulatedFormat("no_rows")?.verdict, .noRows)
        // The made-up numbers must also pass the real thresholds, or the preview would show a state the app can't reach.
        for kind in ["problems", "no_rows"] {
            let r = UsageStore.simulatedFormat(kind)!
            let file = ClaudeUsageScanner.FileResult(mtime: now, size: 0, calls: [], titles: [:], limitHits: [], apiMillis: [:], offset: 0,
                                                     health: .init(lines: r.lines, checked: r.checked, problems: r.problems, version: r.version))
            XCTAssertEqual(verdict([file]).verdict, r.verdict, kind)
        }
    }

    func testFilesWithoutHealthAreLeftOut() {
        var legacy = file(lines: 0, checked: 0)
        legacy.health = nil
        XCTAssertEqual(verdict([legacy, file(lines: 400, checked: 100)]).checked, 100)
    }
}
