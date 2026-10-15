import AppKit
import SwiftUI

/// The five poses each mascot was drawn in. Mood is chosen from how much of the window is left.
enum Mood: String, CaseIterable {
    case fresh, focused, tired, asleep, waking

    /// - used: percent of the session window used, when known.
    /// - justReset: the window reset within the last minute or so.
    static func of(_ s: WindowStatus, justReset: Bool) -> Mood {
        if justReset { return .waking }
        if let b = s.blockedUntil, b > Date() { return .asleep }
        switch s.state {
        case .ready, .unavailable: return .fresh
        case .active:
            guard let u = s.usedPercent else { return .focused }
            if u >= 99.5 { return .asleep }
            if u >= 70 { return .tired }
            if u >= 35 { return .focused }
            return .fresh
        }
    }
}

enum MascotArt {
    /// Mascot art exists for these provider ids; custom providers have none.
    static let providers = ["claude", "codex", "gemini", "antigravity"]

    private static var cache: [String: NSImage] = [:]

    struct Eye { var rect: CGRect; var color: Color }
    private static let eyeMap: [String: [Eye]] = {
        guard let url = Bundle.main.url(forResource: "eyes", withExtension: "json"),
              let d = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: [[String: Any]]] else { return [:] }
        var out: [String: [Eye]] = [:]
        for (k, list) in obj {
            out[k] = list.compactMap { e in
                guard let r = e["r"] as? [Double], r.count == 4, let c = e["c"] as? String, let v = UInt32(c, radix: 16) else { return nil }
                return Eye(rect: CGRect(x: r[0], y: r[1], width: r[2], height: r[3]),
                           color: Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255))
            }
        }
        return out
    }()

    static func eyes(_ provider: String, _ mood: Mood) -> [Eye] { eyeMap["\(provider)-\(mood.rawValue)"] ?? [] }

    static func image(_ provider: String, _ mood: Mood) -> NSImage? {
        let key = "\(provider)-\(mood.rawValue)"
        if let i = cache[key] { return i }
        guard let url = Bundle.main.url(forResource: key, withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[key] = img
        return img
    }
}

/// Where the mascots live on screen.
enum Placement: String, CaseIterable, Identifiable {
    case float, perch, notch, dock
    var id: String { rawValue }
    var label: String {
        switch self {
        case .float: return "Anywhere"
        case .perch: return "On the active window"
        case .notch: return "Beside the notch"
        case .dock: return "Above the Dock"
        }
    }
}
