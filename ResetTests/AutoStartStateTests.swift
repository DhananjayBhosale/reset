import XCTest
@testable import Reset

/// Auto-start bookkeeping across passes and across a restart of the app.
final class AutoStartStateTests: XCTestCase {
    private var dir: URL!
    private var url: URL { dir.appendingPathComponent("auto-start.json") }
    private let reset = Date(timeIntervalSince1970: 1_772_557_800)   // a window's end

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func claude(_ state: WindowStatus.State) -> WindowStatus {
        WindowStatus(id: "claude", name: "Claude", state: state, usedPercent: nil, isEstimate: false, source: "",
                     secondary: nil, canAutoStart: true)
    }
    private func on(_ s: WindowStatus) -> Bool { true }

    func testWatchedWindowEndingMakesAKickDue() {
        var a = AutoStartState()
        a.track([claude(.active(resetsAt: reset))], now: reset.addingTimeInterval(-600), wantsAutoStart: on)
        XCTAssertEqual(a.lastSeenReset["claude"], reset)
        XCTAssertNil(a.kickDue["claude"])
        a.track([claude(.ready)], now: reset.addingTimeInterval(30), wantsAutoStart: on)
        XCTAssertEqual(a.kickDue["claude"], .init(reset: reset, attempts: 0))
        XCTAssertNil(a.lastSeenReset["claude"])
    }

    func testNothingIsDueWithoutAutoStartOrBeforeTheReset() {
        var a = AutoStartState(lastSeenReset: ["claude": reset])
        a.track([claude(.ready)], now: reset.addingTimeInterval(-60), wantsAutoStart: on)
        XCTAssertNil(a.kickDue["claude"], "the reset hasn't passed yet")
        XCTAssertEqual(a.lastSeenReset["claude"], reset)
        a.track([claude(.ready)], now: reset.addingTimeInterval(60)) { _ in false }
        XCTAssertNil(a.kickDue["claude"], "auto-start is off")
    }

    func testToolsWithoutAutoStartAreNotTracked() {
        // A closed Antigravity once left a reset from two days earlier in the saved state.
        var a = AutoStartState(lastSeenReset: ["antigravity": reset.addingTimeInterval(-2 * 86400)],
                               kickDue: ["antigravity": .init(reset: reset, attempts: 1)])
        let ag = WindowStatus(id: "antigravity", name: "Antigravity", state: .unavailable("closed"), usedPercent: nil,
                              isEstimate: false, source: "", secondary: nil, canAutoStart: false)
        a.track([ag, claude(.active(resetsAt: reset))], now: reset.addingTimeInterval(-60)) { $0.canAutoStart && $0.id == "claude" }
        XCTAssertNil(a.lastSeenReset["antigravity"])
        XCTAssertNil(a.kickDue["antigravity"])
        XCTAssertEqual(a.lastSeenReset["claude"], reset, "tools that do auto-start are still tracked")
    }

    func testTurningAutoStartOnAfterTheResetDoesNotFireIt() {
        var a = AutoStartState(lastSeenReset: ["claude": reset], armedAt: ["claude": reset.addingTimeInterval(10)])
        a.track([claude(.ready)], now: reset.addingTimeInterval(60), wantsAutoStart: on)
        XCTAssertNil(a.kickDue["claude"])
    }

    func testANewWindowClearsPendingKicks() {
        var a = AutoStartState(kickDue: ["claude": .init(reset: reset, attempts: 2)], pausedKick: ["claude": reset])
        a.track([claude(.active(resetsAt: reset.addingTimeInterval(5 * 3600)))], now: reset.addingTimeInterval(600), wantsAutoStart: on)
        XCTAssertNil(a.kickDue["claude"])
        XCTAssertNil(a.pausedKick["claude"])
    }

    // MARK: Across a restart

    func testResetThatPassedWhileTheAppWasClosedIsCaughtUp() {
        var before = AutoStartState()
        before.track([claude(.active(resetsAt: reset))], now: reset.addingTimeInterval(-3600), wantsAutoStart: on)
        before.save(to: url)
        // Reset quits, the window ends, Reset starts again an hour later.
        var after = AutoStartState.load(from: url, legacy: nil)
        after.track([claude(.ready)], now: reset.addingTimeInterval(3600), wantsAutoStart: on)
        XCTAssertEqual(after.kickDue["claude"], .init(reset: reset, attempts: 0))
    }

    func testRetryInProgressAndPausedKickSurviveARestart() {
        let a = AutoStartState(lastSeenReset: ["codex": reset], kickDue: ["claude": .init(reset: reset, attempts: 2)],
                               pausedKick: ["claude": reset], armedAt: ["claude": reset.addingTimeInterval(-86400)])
        a.save(to: url)
        XCTAssertEqual(AutoStartState.load(from: url, legacy: nil), a)
    }

    func testOldSavedResetTimesCarryOver() {
        let suite = "reset-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["claude": reset], forKey: "lastSeenReset")
        let a = AutoStartState.load(from: url, legacy: defaults)
        XCTAssertEqual(a.lastSeenReset, ["claude": reset])
        XCTAssertEqual(a.kickDue, [:])
    }

    func testAFileOnDiskWinsOverOldSettings() {
        let suite = "reset-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["claude": reset.addingTimeInterval(-86400)], forKey: "lastSeenReset")
        AutoStartState(lastSeenReset: ["claude": reset]).save(to: url)
        XCTAssertEqual(AutoStartState.load(from: url, legacy: defaults).lastSeenReset, ["claude": reset])
    }
}
