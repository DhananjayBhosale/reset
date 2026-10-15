import XCTest
@testable import Reset

/// "Report a problem" must help without giving anything personal away.
final class ProblemReportTests: XCTestCase {
    private let facts = ProblemReport.Facts(
        resetVersion: "0.3.6", macOS: "27.2.0", macModel: "Mac16,1", toolsOn: ["Claude", "Codex"],
        liveUsage: "working", claudeAccuracy: "solid", logFormat: "ok", lastAutoStart: "started (claude)",
        stayAwake: "When plugged in", phoneAlerts: true, widgetsSigned: false)

    func testBodyCarriesTheDiagnostics() {
        let b = ProblemReport.body(facts)
        for needle in ["Reset 0.3.6, macOS 27.2.0, Mac16,1", "Tools on: Claude, Codex", "Live usage: working",
                       "Claude numbers: solid", "Log format check: ok", "Last auto-start: started (claude)",
                       "Stay awake: When plugged in", "Phone alerts: on", "Widgets available (signed build): no"] {
            XCTAssertTrue(b.contains(needle), needle)
        }
        XCTAssertTrue(b.contains("**What happened?**"), "leaves room for the person's own words")
    }

    func testURLOpensANewIssueWithTitleAndBody() throws {
        let url = try XCTUnwrap(ProblemReport.url(repo: "https://github.com/example/reset", facts: facts))
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/example/reset/issues/new")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "body" }?.value, ProblemReport.body(facts), "survives encoding intact")
        XCTAssertLessThan(url.absoluteString.count, 6000, "well under browser and GitHub URL limits")
    }

    func testTheRealReportLeaksNothingPersonal() throws {
        // Built from this Mac's real settings and state, exactly as the button would.
        let store = Store()
        // Only the title and body: the link's own path is the public repo address (github.com/<owner>/reset).
        let url = try XCTUnwrap(store.problemReportURL())
        let text = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap(\.value).joined(separator: "\n")
        XCTAssertTrue(text.contains("Diagnostics"))
        XCTAssertFalse(text.contains(NSHomeDirectory()), "no home folder or project paths")
        XCTAssertFalse(text.contains("/Users/"), "no file paths at all")
        if !store.ntfyTopic.isEmpty { XCTAssertFalse(text.contains(store.ntfyTopic), "never the phone topic") }
        XCTAssertFalse(!NSUserName().isEmpty && text.contains(NSUserName()), "no account name")
        XCTAssertFalse(text.contains("$"), "no money amounts")
        XCTAssertFalse(text.range(of: #"\d+(\.\d+)?%"#, options: .regularExpression) != nil, "no usage percentages")
    }
}
