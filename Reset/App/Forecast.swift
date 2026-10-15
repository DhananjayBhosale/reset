import Foundation

/// Predicts when the current window will hit its limit from recent usage readings, and warns once per
/// window if that happens before the reset. Only runs on real (live) percentages, never on estimates.
///
/// Saved to forecast.json after each reading, so a restart (an update, a reboot) doesn't blank the run-out
/// warning for the 10 minutes it takes to gather readings again, and doesn't warn a second time for a window
/// it already warned about.
final class Forecast {
    struct Reading: Codable { var t: Date; var used: Double }

    private(set) var readings: [Reading] = []
    private var windowEnd: Date?
    private var warnedFor: Date?

    /// Projected time the window runs out, if it is on course to happen before the reset.
    private(set) var runsOutAt: Date?

    private let storeURL: URL?

    static var defaultURL: URL { WidgetSnapshot.url.deletingLastPathComponent().appendingPathComponent("forecast.json") }

    private struct Saved: Codable {
        var readings: [Reading]
        var windowEnd: Date?
        var warnedFor: Date?
    }

    /// With no `storeURL` nothing is read or written (tests, demo).
    init(storeURL: URL? = nil, now: Date = Date()) {
        self.storeURL = storeURL
        guard let storeURL, let d = try? Data(contentsOf: storeURL) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        guard let s = try? dec.decode(Saved.self, from: d) else { return }
        // A window that has already ended says nothing about the next one.
        guard let end = s.windowEnd, end > now else { return }
        windowEnd = end
        warnedFor = s.warnedFor
        readings = s.readings.filter { now.timeIntervalSince($0.t) < 45 * 60 && $0.t <= now }
        runsOutAt = project(now: now)
    }

    private func save() {
        guard let storeURL else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        guard let d = try? enc.encode(Saved(readings: readings, windowEnd: windowEnd, warnedFor: warnedFor)) else { return }
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: storeURL, options: .atomic)
    }

    func record(used: Double, resetsAt: Date?, now: Date = Date()) {
        // A new window starts a new series.
        if resetsAt != windowEnd {
            if let a = resetsAt, let b = windowEnd, abs(a.timeIntervalSince(b)) < 120 {} else {
                readings = []
                windowEnd = resetsAt
                runsOutAt = nil
            }
        }
        if let last = readings.last, now.timeIntervalSince(last.t) < 60 { return }
        readings.append(Reading(t: now, used: used))
        readings = readings.filter { now.timeIntervalSince($0.t) < 45 * 60 }
        runsOutAt = project(now: now)
        save()
    }

    /// Least-squares slope over the last 45 minutes, in percent per second.
    private func project(now: Date) -> Date? {
        guard readings.count >= 3, let end = windowEnd, let first = readings.first,
              now.timeIntervalSince(first.t) >= 10 * 60 else { return nil }
        let xs = readings.map { $0.t.timeIntervalSince(first.t) }, ys = readings.map(\.used)
        let n = Double(xs.count), mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard den > 0 else { return nil }
        let slope = num / den
        guard slope > 0, let current = ys.last, current < 100 else { return nil }
        let at = now.addingTimeInterval((100 - current) / slope)
        // Only worth saying if it lands meaningfully before the reset.
        return at < end.addingTimeInterval(-5 * 60) ? at : nil
    }

    /// True once per window, the first time a run-out before the reset is projected.
    func shouldWarn() -> Bool {
        guard let end = windowEnd, runsOutAt != nil, warnedFor != end else { return false }
        warnedFor = end
        save()
        return true
    }
}
