import XCTest
@testable import Reset

/// The fuse widget's numbers: where the spark is, where the pace runs out, and how much to slow down.
final class FuseTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_772_442_000)

    private func claude(resetIn: TimeInterval?, used: Double? = 58, ready: Bool = false,
                        blockedFor: TimeInterval? = nil, available: Bool = true) -> WidgetSnapshot.Provider {
        .init(id: "claude", name: "Claude", resetsAt: resetIn.map { now.addingTimeInterval($0) }, ready: ready,
              available: available, used: used, blockedUntil: blockedFor.map { now.addingTimeInterval($0) })
    }

    func testOnPaceSparkSitsAtTheTimeElapsed() {
        // 2h of a 5h window gone, so the spark is 40% along.
        let m = FuseModel.make(claude(resetIn: 3 * 3600), runsOutAt: nil, now: now)
        XCTAssertEqual(m.state, .onPace)
        XCTAssertEqual(m.progress, 0.4, accuracy: 1e-9)
        XCTAssertEqual(m.percentLeft, 42)
        XCTAssertNil(m.runOutProgress)
        XCTAssertNil(m.slowDownPercent)
        XCTAssertEqual(m.start, now.addingTimeInterval(-2 * 3600))
    }

    func testRunningOutPlacesTheFlagAndWorksOutTheSlowDown() {
        // Reset in 2h, pace runs dry in 1h 36m: usage has to last 120 min instead of 96, a 20% slower pace.
        let m = FuseModel.make(claude(resetIn: 2 * 3600), runsOutAt: now.addingTimeInterval(96 * 60), now: now)
        XCTAssertEqual(m.state, .runningOut)
        XCTAssertEqual(m.runsOutAt, now.addingTimeInterval(96 * 60))
        XCTAssertEqual(m.slowDownPercent, 20)
        // Window started 3h ago; the flag is at 3h + 1h36m of 5h.
        XCTAssertEqual(m.runOutProgress!, (3 * 60 + 96) / 300.0, accuracy: 1e-9)
        XCTAssertGreaterThan(m.runOutProgress!, m.progress)
    }

    func testSlowDownRoundsUpSoTheAdviceIsEnough() {
        // Has to last 100 min instead of 99: 1% slower, never "0%".
        let m = FuseModel.make(claude(resetIn: 100 * 60), runsOutAt: now.addingTimeInterval(99 * 60), now: now)
        XCTAssertEqual(m.slowDownPercent, 1)
        let tight = FuseModel.make(claude(resetIn: 100 * 60), runsOutAt: now.addingTimeInterval(60), now: now)
        XCTAssertEqual(tight.slowDownPercent, 99, "capped below 100")
    }

    func testStaleForecastsAreIgnored() {
        XCTAssertEqual(FuseModel.make(claude(resetIn: 3600), runsOutAt: now.addingTimeInterval(-60), now: now).state, .onPace,
                       "already in the past")
        XCTAssertEqual(FuseModel.make(claude(resetIn: 3600), runsOutAt: now.addingTimeInterval(7200), now: now).state, .onPace,
                       "after the reset means it lasts")
    }

    func testOtherStates() {
        XCTAssertEqual(FuseModel.make(nil, runsOutAt: nil, now: now).state, .unknown)
        XCTAssertEqual(FuseModel.make(claude(resetIn: 3600, available: false), runsOutAt: nil, now: now).state, .unknown)
        XCTAssertEqual(FuseModel.make(claude(resetIn: nil, used: 0, ready: true), runsOutAt: nil, now: now).state, .ready)
        XCTAssertEqual(FuseModel.make(claude(resetIn: -60), runsOutAt: nil, now: now).state, .ready, "reset passed between snapshots")
        XCTAssertEqual(FuseModel.make(claude(resetIn: 3600, blockedFor: 86400), runsOutAt: nil, now: now).state,
                       .blocked(until: now.addingTimeInterval(86400)))
    }

    func testUnknownUsageStillDrawsTheFuse() {
        let m = FuseModel.make(claude(resetIn: 3600, used: nil), runsOutAt: nil, now: now)
        XCTAssertEqual(m.state, .onPace)
        XCTAssertNil(m.percentLeft)
        XCTAssertEqual(m.progress, 0.8, accuracy: 1e-9)
    }

    func testWidgetsReloadWhenTheForecastMovesTenMinutes() {
        let p = [claude(resetIn: 3600)]
        let a = Store.widgetState(p, runsOutAt: now.addingTimeInterval(1800))
        XCTAssertEqual(a, Store.widgetState(p, runsOutAt: now.addingTimeInterval(1800 + 60)), "a minute's drift doesn't spend a reload")
        XCTAssertNotEqual(a, Store.widgetState(p, runsOutAt: now.addingTimeInterval(1800 + 900)))
        XCTAssertNotEqual(a, Store.widgetState(p, runsOutAt: nil), "the flag appearing or going away reloads")
    }
}

/// Widgets keep one snapshot for up to an hour, so day and month totals are read as of the entry's date.
final class WidgetDayRolloverTests: XCTestCase {
    func testAfterMidnightTodayStartsAgainAndYesterdayIsTheOldToday() {
        let cal = Calendar.current
        let evening = cal.date(bySettingHour: 23, minute: 50, second: 0, of: Date(timeIntervalSince1970: 1_772_442_000))!
        var s = WidgetSnapshot(updated: evening, providers: [], windows: [], weekCost: 0, cacheHit: 0)
        s.todayCumulative = Array(repeating: 9, count: 24); s.yesterdayCumulative = Array(repeating: 4, count: 24)
        s.monthDays = [1, 2]; s.limitDays = [2]
        XCTAssertEqual(s.dayCurves(on: evening.addingTimeInterval(300)).today.last, 9, "same day: as written")
        let lateNight = evening.addingTimeInterval(20 * 60)
        XCTAssertEqual(s.dayCurves(on: lateNight).today.last, 0)
        XCTAssertEqual(s.dayCurves(on: lateNight).yesterday.last, 9)
        XCTAssertEqual(s.dayCurves(on: evening.addingTimeInterval(2 * 86400)).yesterday.last, 0, "two days on: nothing known")
        XCTAssertEqual(s.month(on: evening).days, [1, 2])
        XCTAssertEqual(s.month(on: cal.date(byAdding: .month, value: 1, to: evening)!).days, [], "a new month starts empty")
    }
}
