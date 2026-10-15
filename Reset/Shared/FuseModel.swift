import Foundation

/// The fuse widget's picture of the Claude window: the fuse runs from the window's start to its reset, the
/// spark sits at now, and a flag marks where the current pace runs out, if that comes before the reset.
/// Shared with the app so the numbers can be tested; the widget only draws them.
struct FuseModel: Equatable {
    enum State: Equatable {
        /// No usage data yet.
        case unknown
        /// No window running; the next message lights the fuse.
        case ready
        /// A longer limit is exhausted, so a fresh window wouldn't help until then.
        case blocked(until: Date)
        /// A window is running and, at the current pace, lasts to the reset.
        case onPace
        /// A window is running and the current pace runs out before the reset.
        case runningOut
    }

    var state: State
    var start: Date?
    var reset: Date?
    /// How far the spark has burned along the fuse, 0...1.
    var progress: Double = 0
    var runsOutAt: Date?
    /// Where the run-out flag sits along the fuse, 0...1.
    var runOutProgress: Double?
    var percentLeft: Int?
    /// How much slower, in percent, the pace has to get for the window to last until the reset.
    var slowDownPercent: Int?

    static let window: TimeInterval = 5 * 3600

    static func make(_ p: WidgetSnapshot.Provider?, runsOutAt: Date?, now: Date) -> FuseModel {
        guard let p, p.available else { return FuseModel(state: .unknown) }
        if let b = p.blockedUntil, b > now { return FuseModel(state: .blocked(until: b)) }
        // A reset time that has already passed means the window ended between snapshots.
        guard !p.ready, let reset = p.resetsAt, reset > now else { return FuseModel(state: .ready, percentLeft: 100) }

        let start = reset.addingTimeInterval(-window)
        var m = FuseModel(state: .onPace, start: start, reset: reset)
        m.progress = min(1, max(0, now.timeIntervalSince(start) / window))
        m.percentLeft = p.used.map { Int(max(0, 100 - $0).rounded()) }

        // The forecast only counts when it lands between now and the reset; anything else is stale.
        if let out = runsOutAt, out > now, out < reset {
            m.state = .runningOut
            m.runsOutAt = out
            m.runOutProgress = min(1, max(0, out.timeIntervalSince(start) / window))
            // Usage left lasts (out - now) at today's pace and has to last (reset - now): the pace must drop
            // by the missing share. Rounded up, so following the advice is always enough; the tiny tolerance keeps
            // float noise (an exact 1% computing as 1.0000000000000009%) from rounding up a whole extra point.
            let share = 1 - out.timeIntervalSince(now) / reset.timeIntervalSince(now)
            m.slowDownPercent = min(99, max(1, Int((share * 100 - 1e-9).rounded(.up))))
        }
        return m
    }
}
