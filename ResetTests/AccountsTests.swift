import XCTest
@testable import Reset

/// Two Claude accounts (say a Team org and a personal Pro plan) get separate windows.
final class AccountsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_772_442_000)
    private func act(_ minutesAgo: Double, _ org: String?) -> TranscriptScanner.Event {
        .init(time: now.addingTimeInterval(-minutesAgo * 60), kind: .activity, org: org)
    }

    func testMainAccountIsTheCLIsOtherwiseTheMostRecent() {
        let events = [act(300, "team"), act(10, "pro")]
        XCTAssertEqual(ClaudeSource.mainOrg(cliOrg: "team", events: events), "team")
        XCTAssertEqual(ClaudeSource.mainOrg(cliOrg: nil, events: events), "pro", "without the CLI, the latest activity decides")
    }

    func testOtherAccountsAreThoseWithActivity() {
        let events = [act(20, "team"), act(500, "pro"), act(30, nil),
                      .init(time: now, kind: .fiveHourLimit(now.addingTimeInterval(3600)), org: "other")]
        XCTAssertEqual(ClaudeSource.otherOrgs(events: events, main: "team"), ["pro"], "a limit row alone isn't use")
        XCTAssertEqual(ClaudeSource.otherOrgs(events: [act(20, "team")], main: "team"), [], "one account: nothing extra")
    }

    func testEachAccountGetsItsOwnWindow() {
        // Team started a window 40 minutes ago; Pro started one 4 hours ago.
        let team = [act(40, "team")], pro = [act(240, "pro")]
        let t = ClaudeSource.status(id: "claude", name: "Claude · Team", events: team, org: nil, now: now, canAutoStart: true)
        let p = ClaudeSource.status(id: "claude-pro", name: "Claude · Pro", events: pro, org: nil, now: now, canAutoStart: false)
        XCTAssertNotEqual(t.resetsAt, p.resetsAt)
        XCTAssertGreaterThan(t.resetsAt!, p.resetsAt!, "Pro's window resets first")
        XCTAssertFalse(p.canAutoStart, "auto-start goes through the CLI's account")
    }

    func testNames() {
        XCTAssertEqual(ClaudeSource.planLabel("team"), "Team")
        XCTAssertEqual(ClaudeSource.planLabel("max"), "Max")
        XCTAssertNil(ClaudeSource.planLabel(nil))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("plan.json")
        try! #"{"samples":[{"t":1772442000000,"org":"pro-org","u":{"fh":10,"sd":100}},{"t":1772442000000,"org":"team-org","u":{"fh":5}}]}"#
            .write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(ClaudeSource.otherLabel(org: "pro-org", url: url), "Pro", "a weekly limit means Pro or Max")
        XCTAssertEqual(ClaudeSource.otherLabel(org: "team-org", url: url), "other account")
    }

    func testTranscriptEventsCarryTheirSessionsOrg() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("-Users-example-proj")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lines = [#"{"type":"attachment","attachment":{"type":"credential_org","organizationUuid":"org-pro-1234"}}"#,
                     #"{"type":"assistant","timestamp":"2026-03-02T09:14:05.120Z","requestId":"r1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"output_tokens":5}}}"#]
        try (lines.joined(separator: "\n") + "\n").write(to: folder.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
        let events = TranscriptScanner().events(under: root, since: .distantPast)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.org, "org-pro-1234")
    }

    func testMenuBarNamesTheSecondAccountByPlan() {
        let pro = WindowStatus(id: "claude-pro12345", name: "Claude · Pro", state: .active(resetsAt: now.addingTimeInterval(3600)),
                               usedPercent: 30, isEstimate: true, source: "", secondary: nil, canAutoStart: false)
        XCTAssertEqual(MenuBarGlance.make(ready: nil, soonest: pro, blocked: nil, runsOutAt: nil, signedOut: false, now: now)?.text,
                       "Pro 1:00 · 70%")
    }
}
