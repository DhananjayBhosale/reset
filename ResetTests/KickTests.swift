import XCTest
import IOKit.pwr_mgt
@testable import Reset

/// Auto-start outcomes, judged the way the real failures looked: a signed-out run, a rejected sign-in,
/// a run Reset had to stop, and a normal success.
final class KickOutcomeTests: XCTestCase {
    private func row(_ json: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    }

    /// What a successful kick writes.
    private var reply: [String: Any] {
        row(#"{"type":"assistant","requestId":"req_1","timestamp":"2026-10-15T09:14:05.120Z","message":{"id":"msg_1","model":"claude-haiku-5-5","content":[{"type":"text","text":"Hi!"}],"usage":{"input_tokens":8,"output_tokens":5}}}"#)
    }
    /// What Claude Code writes when its sign-in is present but refused (seen on 10-14 and 10-15).
    private var authFailed: [String: Any] {
        row(#"{"type":"assistant","requestId":"req_2","timestamp":"2026-10-14T13:12:01.000Z","isApiErrorMessage":true,"error":"authentication_failed","message":{"id":"x","model":"<synthetic>","content":[{"type":"text","text":"Failed to authenticate."}]}}"#)
    }

    func testRealReplyIsStarted() {
        XCTAssertEqual(KickOutcome.classify(status: 0, timedOut: false, output: "Hi!", lastAssistant: reply), .started)
    }

    func testRejectedSignInIsSignedOut() {
        let out = "Failed to authenticate. API Error: 401 OAuth access token is invalid."
        XCTAssertEqual(KickOutcome.classify(status: 1, timedOut: false, output: out, lastAssistant: authFailed), .signedOut)
        XCTAssertEqual(KickOutcome.classify(status: 0, timedOut: false, output: "", lastAssistant: authFailed), .signedOut,
                       "the error row wins even over a clean exit")
    }

    func testNoSignInAtAllIsSignedOut() {
        XCTAssertEqual(KickOutcome.classify(status: 1, timedOut: false, output: "Not logged in · Please run /login\n", lastAssistant: nil), .signedOut)
    }

    func testRunStoppedAtTheTimeLimitIsTimedOut() {
        // The 10-14 runs at 04:55, 05:13 and 05:46: about 188 s, no API time, no reply row, stopped by Reset.
        XCTAssertEqual(KickOutcome.classify(status: 15, timedOut: true, output: "", lastAssistant: nil), .timedOut)
        XCTAssertEqual(KickOutcome.classify(status: 15, timedOut: true, output: "", lastAssistant: reply), .started,
                       "a reply that landed before the stop still opened the window")
    }

    func testLimitStillInForceIsRateLimited() {
        let limited = row(#"{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","message":{"model":"<synthetic>"}}"#)
        XCTAssertEqual(KickOutcome.classify(status: 1, timedOut: false, output: "", lastAssistant: limited), .rateLimited)
    }

    func testOtherFailuresKeepTheirReason() {
        let server = row(#"{"type":"assistant","isApiErrorMessage":true,"error":"server_error","message":{"model":"<synthetic>"}}"#)
        XCTAssertEqual(KickOutcome.classify(status: 1, timedOut: false, output: "", lastAssistant: server), .failed("Claude Code reported server_error"))
        XCTAssertEqual(KickOutcome.classify(status: 1, timedOut: false, output: "starting\nConnection error.\n", lastAssistant: nil),
                       .failed("exit 1: Connection error."))
    }

    func testCleanExitWithoutEvidenceIsTrusted() {
        XCTAssertEqual(KickOutcome.classify(status: 0, timedOut: false, output: "", lastAssistant: nil), .started, "Codex, or no transcript found")
        XCTAssertEqual(KickOutcome.classify(status: 0, timedOut: false, output: "You can check your rate limit in settings", lastAssistant: nil), .started,
                       "a normal reply mentioning limits isn't a failure")
    }

    // MARK: Finding the kick's transcript

    func testFindsTheLastAssistantRowOfTheNewestKickTranscript() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let kickDir = URL(fileURLWithPath: "/Users/example/Library/Application Support/Reset/kick")
        let folder = root.appendingPathComponent("-Users-example-Library-Application-Support-Reset-kick")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let since = Date()

        let old = folder.appendingPathComponent("old.jsonl")
        try #"{"type":"assistant","error":"authentication_failed","isApiErrorMessage":true,"message":{"model":"<synthetic>"}}"#
            .appending("\n").write(to: old, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: since.addingTimeInterval(-3600)], ofItemAtPath: old.path)

        let new = folder.appendingPathComponent("new.jsonl")
        let lines = [#"{"type":"user","message":{"content":"hi"}}"#,
                     #"{"type":"assistant","message":{"id":"a","model":"claude-haiku-5-5","usage":{"output_tokens":1}}}"#,
                     #"{"type":"assistant","message":{"id":"b","model":"claude-haiku-5-5","usage":{"output_tokens":5}}}"#,
                     #"{"type":"cost-state","totalAPIDuration":1500}"#]
        try (lines.joined(separator: "\n") + "\n").write(to: new, atomically: true, encoding: .utf8)

        let found = Kicker.lastAssistantRow(kickDir: kickDir, since: since, projects: root)
        XCTAssertEqual((found?["message"] as? [String: Any])?["id"] as? String, "b", "newest file, last assistant row")

        try FileManager.default.removeItem(at: new)
        XCTAssertNil(Kicker.lastAssistantRow(kickDir: kickDir, since: since, projects: root), "files from before the run don't count")
    }

    // MARK: The real runner

    /// Runs a command through Kicker and waits for its outcome. "probe" isn't "claude", so no transcript is looked up.
    private func run(_ command: String, timeLimit: TimeInterval = 30) -> KickOutcome? {
        let k = Kicker()
        k.timeLimit = timeLimit
        let done = expectation(description: "kick")
        var outcome: KickOutcome?
        k.kick("probe", name: "Probe", command: command, log: { _ in }) { outcome = $0; done.fulfill() }
        wait(for: [done], timeout: timeLimit + 15)
        return outcome
    }

    func testRunnerReportsAnExitedSignedOutCommand() {
        XCTAssertEqual(run(#"echo "Not logged in · Please run /login" >&2; exit 1"#), .signedOut)
    }

    func testRunnerReportsACleanRun() {
        XCTAssertEqual(run("echo hi"), .started)
    }

    func testRunnerStopsAHungCommandAndSaysSo() {
        XCTAssertEqual(run("sleep 30", timeLimit: 1), .timedOut)
    }

    // MARK: Staying awake for a run

    /// This process's power assertions with the given name, as macOS reports them.
    private func assertions(named name: String) -> [[String: Any]] {
        var out: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&out) == kIOReturnSuccess,
              let all = out?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        return (all[NSNumber(value: getpid())] ?? []).filter { ($0["AssertName"] as? String) == name }
    }

    func testAwakeHoldTakesBothAssertionsAndLetsGo() {
        let name = "Reset test hold \(UUID().uuidString)"
        let hold = AwakeHold(reason: name, seconds: 60)
        XCTAssertEqual(hold.ids.count, 2)
        let types = Set(assertions(named: name).compactMap { $0["AssertType"] as? String })
        XCTAssertEqual(types, ["PreventUserIdleSystemSleep", "NetworkClientActive"])
        hold.release()
        hold.release()
        XCTAssertTrue(assertions(named: name).isEmpty, "released, and a second release is harmless")
    }

    func testRunnerHoldsTheMacAwakeOnlyWhileARunIsGoing() {
        let k = Kicker()
        let done = expectation(description: "kick")
        k.kick("probe", name: "Probe", command: "sleep 2", log: { _ in }) { _ in done.fulfill() }
        let during = expectation(description: "checked during the run")
        var held = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            held = self.assertions(named: "Reset is starting your next Probe window").count
            during.fulfill()
        }
        wait(for: [during, done], timeout: 20)
        XCTAssertEqual(held, 2, "held while the command runs")
        XCTAssertTrue(assertions(named: "Reset is starting your next Probe window").isEmpty, "let go when it ends")
    }

    // MARK: Signed-out warning

    func testSignInWarningLastsUntilASuccessOrASignIn() {
        func r(_ kind: String, _ id: String = "claude") -> Store.KickRecord {
            Store.KickRecord(id: id, time: Date(), kind: kind, summary: "")
        }
        XCTAssertFalse(Store.needsSignIn([], id: "claude"))
        XCTAssertTrue(Store.needsSignIn([r("started"), r("signed_out")], id: "claude"))
        XCTAssertTrue(Store.needsSignIn([r("signed_out"), r("started", "codex")], id: "claude"), "other providers don't clear it")
        XCTAssertFalse(Store.needsSignIn([r("signed_out"), r("signed_in")], id: "claude"))
        XCTAssertFalse(Store.needsSignIn([r("signed_out"), r("started")], id: "claude"))
        XCTAssertFalse(Store.needsSignIn([r("signed_out"), r("timed_out")], id: "claude"), "a later run got past the sign-in")
    }
}
