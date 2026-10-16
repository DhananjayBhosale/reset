import Foundation

/// One provider's current rate-limit window, as best we can tell from local data.
struct WindowStatus: Identifiable, Equatable {
    enum State: Equatable {
        /// A window is running and resets at this time.
        case active(resetsAt: Date)
        /// No window is running; the next message starts a fresh one.
        case ready
        /// We could not read anything for this provider.
        case unavailable(String)
    }

    struct Secondary: Equatable {
        var label: String
        var resetsAt: Date
        var usedPercent: Double?
    }

    let id: String
    var name: String
    var state: State
    /// 0...100 when the provider reports it.
    var usedPercent: Double?
    /// True when the reset time is inferred from activity rather than reported by the provider.
    var isEstimate: Bool
    var source: String
    var secondary: Secondary?
    /// Whether the auto-start toggle makes sense for this provider.
    var canAutoStart: Bool
    /// A longer limit (weekly, monthly) is exhausted until this time, so a fresh session window would not help.
    var blockedUntil: Date? = nil
    /// When `usedPercent` was measured, if it is not live.
    var usageAsOf: Date? = nil
    /// The most recent real API response seen in this tool's logs, for pacing how often live usage is fetched.
    var lastActivity: Date? = nil

    var resetsAt: Date? {
        if case .active(let d) = state { return d }
        return nil
    }
}

protocol WindowSource {
    var id: String { get }
    func read(now: Date) -> WindowStatus
}

enum Fmt {
    /// "2h 14m", "14m", "45s"
    static func countdown(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval.rounded()))
        let h = s / 3600, m = (s % 3600) / 60
        if h >= 24 { return "\(h / 24)d \(h % 24)h" }
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    /// Compact form for the menu bar: "2:14", "0:09"
    static func short(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval))
        let h = s / 3600, m = (s % 3600) / 60
        if h >= 24 { return "\(h / 24)d" }
        return "\(h):\(String(format: "%02d", m))"
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    static let dayClock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()

    static func when(_ date: Date, now: Date = Date()) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? clock.string(from: date) : dayClock.string(from: date)
    }
}
