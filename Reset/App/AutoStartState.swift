import Foundation

/// Auto-start bookkeeping, saved to ~/Library/Application Support/Reset/auto-start.json so a restart
/// (an update, a reboot) doesn't forget a retry in progress or a kick waiting on a sign-in.
///
/// A kick is only due after Reset itself watched a window run out while auto-start was on, so switching the
/// toggle on never fires a command straight away, and a source that stays ready after a kick doesn't trigger
/// another one.
struct AutoStartState: Codable, Equatable {
    struct Due: Codable, Equatable {
        var reset: Date
        var attempts: Int
    }

    /// The reset time of each provider's running window, remembered until it passes.
    var lastSeenReset: [String: Date] = [:]
    /// Kicks waiting to run, with how many tries have failed so far.
    var kickDue: [String: Due] = [:]
    /// A kick stopped because Claude Code was signed out, kept so signing in can run it straight away.
    var pausedKick: [String: Date] = [:]
    /// When auto-start was last switched on per provider; resets watched before then don't count.
    var armedAt: [String: Date] = [:]

    /// One pass over fresh statuses: remember running windows' reset times, and mark a kick due for a watched
    /// window that has ended. The first pass after launch is the same pass, which is how a reset that passed
    /// while Reset wasn't running gets caught up. A new window (yours or a kick's) clears anything pending.
    mutating func track(_ statuses: [WindowStatus], now: Date, wantsAutoStart: (WindowStatus) -> Bool) {
        for s in statuses {
            if let r = s.resetsAt {
                lastSeenReset[s.id] = r
                kickDue[s.id] = nil
                pausedKick[s.id] = nil
            } else if s.state == .ready, let r = lastSeenReset[s.id], r <= now {
                lastSeenReset[s.id] = nil
                if wantsAutoStart(s), r > (armedAt[s.id] ?? .distantPast) {
                    kickDue[s.id] = Due(reset: r, attempts: 0)
                }
            }
        }
    }

    static var url: URL { WidgetSnapshot.url.deletingLastPathComponent().appendingPathComponent("auto-start.json") }

    /// Before this file existed, only the watched reset times were kept, in UserDefaults; they carry over once.
    static func load(from url: URL, legacy: UserDefaults? = .standard) -> AutoStartState {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        if let d = try? Data(contentsOf: url), let s = try? dec.decode(AutoStartState.self, from: d) { return s }
        var s = AutoStartState()
        if let old = legacy?.dictionary(forKey: "lastSeenReset") as? [String: Date] { s.lastSeenReset = old }
        return s
    }

    func save(to url: URL) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        guard let d = try? enc.encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: url, options: .atomic)
    }
}
