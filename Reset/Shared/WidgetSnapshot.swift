import Foundation

/// What the desktop widgets show, written by the app to ~/Library/Application Support/Reset/widget.json.
/// The widget extension is sandboxed and only allowed to read that one folder.
struct WidgetSnapshot: Codable {
    struct Provider: Codable, Identifiable {
        var id: String
        var name: String
        var resetsAt: Date?
        var ready: Bool
        var available: Bool
        var used: Double?
        var blockedUntil: Date?
        /// Why these numbers are a guess (see UsageAccuracy), or nil when they're solid. Optional for old snapshots.
        var estimate: String? = nil
    }
    struct Window: Codable {
        var start: Date
        var end: Date
        var autoStart: Bool
        var hitLimit: Bool
    }

    var updated: Date
    var look: Look?
    var providers: [Provider]
    var windows: [Window]
    var weekCost: Double
    var weekMultiple: Double?
    var cacheHit: Double
    // Month view, for the Value and Month widgets. Optional so older snapshots still decode.
    var monthCost: Double?
    var monthMultiple: Double?
    var monthCacheSaved: Double?
    var monthTokens: Int?
    /// Cache read, cache write, output, input.
    var monthMix: [Int]?
    /// Output by weekday (Mon first) and hour, 0...1.
    var heatmap: [[Double]]?
    /// Output per hour today, 0...1.
    var today: [Double]?
    /// API value per day for the last 14 days, oldest first.
    var dailyCost: [Double]?
    /// Cumulative API value by hour, today and yesterday.
    var todayCumulative: [Double]?
    var yesterdayCumulative: [Double]?
    /// Top projects this month by API value.
    var projects: [Project]?
    /// This calendar month: API value per day (index 0 = 1st) and days the 5-hour limit was hit.
    var monthDays: [Double]?
    var limitDays: [Int]?
    /// Projected time the Claude window runs out before its reset, when the pace says so.
    var claudeRunsOutAt: Date?
    /// When a widget's "Start now" was pressed and the app began starting Claude's window; cleared when done.
    var startingAt: Date?

    struct Project: Codable { var name: String; var cost: Double }

    static let folder = "Library/Application Support/Reset"
    static let fileName = "widget.json"

    /// The real home folder, also from inside the widget's sandbox container.
    static var url: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(folder).appendingPathComponent(fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(WidgetSnapshot.self, from: d)
    }

    func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        guard let d = try? enc.encode(self) else { return }
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: Self.url, options: .atomic)
    }

    var claude: Provider? { providers.first { $0.id == "claude" } }
}
