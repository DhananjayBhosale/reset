import XCTest
@testable import Reset

/// What the menu bar says, and in which colour.
final class MenuBarGlanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_772_442_000)

    private func s(_ state: WindowStatus.State, id: String = "claude", name: String = "Claude", used: Double? = nil,
                   blockedFor: TimeInterval? = nil) -> WindowStatus {
        var w = WindowStatus(id: id, name: name, state: state, usedPercent: used, isEstimate: false, source: "", secondary: nil, canAutoStart: true)
        w.blockedUntil = blockedFor.map { now.addingTimeInterval($0) }
        return w
    }
    private func active(_ resetIn: TimeInterval, used: Double? = 58) -> WindowStatus {
        s(.active(resetsAt: now.addingTimeInterval(resetIn)), used: used)
    }
    private func glance(ready: WindowStatus? = nil, soonest: WindowStatus? = nil, blocked: WindowStatus? = nil,
                        out: TimeInterval? = nil, signedOut: Bool = false) -> MenuBarGlance? {
        MenuBarGlance.make(ready: ready, soonest: soonest, blocked: blocked, runsOutAt: out.map { now.addingTimeInterval($0) },
                           signedOut: signedOut, now: now)
    }

    func testNormalShowsCountdownAndWhatsLeftInOrange() {
        let g = glance(soonest: active(2 * 3600 + 46 * 60))
        XCTAssertEqual(g?.tone, .normal)
        XCTAssertEqual(g?.text, "2:46 · 42%")
    }

    func testLittleLeftTurnsRed() {
        XCTAssertEqual(glance(soonest: active(1800, used: 91))?.tone, .low)
        XCTAssertEqual(glance(soonest: active(1800, used: 91))?.text, "0:30 · 9%")
        XCTAssertEqual(glance(soonest: active(1800, used: 84))?.tone, .normal, "16% left is still orange")
    }

    func testPaceRunningOutBeforeTheResetTurnsRedWithTheTime() {
        let g = glance(soonest: active(2 * 3600), out: 52 * 60)
        XCTAssertEqual(g?.tone, .runningOut)
        XCTAssertTrue(g?.text.hasPrefix("2:00 · out ") == true)
        XCTAssertEqual(glance(soonest: active(3600), out: 7200)?.tone, .normal, "running out after the reset doesn't matter")
    }

    func testFreshWindowIsGreenReady() {
        XCTAssertEqual(glance(ready: s(.ready)), MenuBarGlance(tone: .ready, text: "ready"))
    }

    func testWeeklyLimitOutranksEverything() {
        let g = glance(ready: s(.ready), soonest: active(3600), blocked: s(.ready, blockedFor: 86400))
        XCTAssertEqual(g?.tone, .blocked)
    }

    func testUnknownUsageShowsOnlyTheCountdown() {
        XCTAssertEqual(glance(soonest: active(3600, used: nil))?.text, "1:00", "no % that would really be the clock")
    }

    func testOtherToolsGetTheirLetterAndSignedOutGetsAWarning() {
        let codex = s(.active(resetsAt: now.addingTimeInterval(3600)), id: "codex", name: "Codex", used: 20)
        XCTAssertEqual(glance(soonest: codex)?.text, "C 1:00 · 80%")
        XCTAssertEqual(glance(soonest: codex, signedOut: true)?.warning, false, "the sign-in warning is Claude's")
        XCTAssertEqual(glance(soonest: active(3600), signedOut: true)?.warning, true)
    }

    func testNothingToShow() {
        XCTAssertNil(glance())
    }

    @MainActor func testPillIsAColouredImageNotATemplate() throws {
        let img = try XCTUnwrap(MenuBarPill.image(MenuBarGlance(tone: .runningOut, text: "0:52 · out 6:40")))
        XCTAssertFalse(img.isTemplate, "a template image would be painted in one colour")
        XCTAssertEqual(img.size.height, 17, accuracy: 1, "fits the menu bar")
        XCTAssertGreaterThan(img.size.width, 60)
    }
}
