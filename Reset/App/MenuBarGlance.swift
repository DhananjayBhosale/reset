import AppKit
import SwiftUI

/// What the menu bar says at a glance, and in which colour: an orange pill with the countdown and how much is
/// left, red when the window is nearly empty or the pace runs out before the reset, green when a fresh window is
/// waiting, and a quiet moon during a weekly limit. Pure, so the choices are tested.
struct MenuBarGlance: Equatable {
    enum Tone: String {
        case normal      // orange pill
        case low         // red pill: little left
        case runningOut  // red pill: today's pace runs out before the reset
        case ready       // green pill
        case blocked     // no pill: a weekly (or longer) limit, nothing to do until it lifts
    }

    var tone: Tone
    var text: String
    /// Claude Code is signed out, so live usage is paused; a small warning sign goes in front.
    var warning = false
    /// What VoiceOver says. The pill is an image, so without this it would be silent; spelled out in words,
    /// because "2:46 · 42%" read aloud is a riddle.
    var spoken = ""

    /// Left at or below this is "low". Matches where the menu's health bar turns red.
    static let lowPercent = 15.0

    /// Which entries the bar speaks for. The account the Claude Code CLI is signed in to ("claude") is the one in
    /// use, so while its window runs the bar follows it alone: a second account that's merely unused reads "ready"
    /// (a green "Pro ready" hid Team's 45% and its run-out warning), and its weekly limit or sooner reset says
    /// nothing about the window you're spending. Otherwise a weekly limit, then a fresh window, then the soonest reset.
    static func pick(_ candidates: [WindowStatus], now: Date)
        -> (ready: WindowStatus?, soonest: WindowStatus?, blocked: WindowStatus?) {
        if let main = candidates.first(where: { $0.id == "claude" }), main.resetsAt != nil,
           (main.blockedUntil ?? .distantPast) <= now {
            return (nil, main, nil)
        }
        return (candidates.first { $0.state == .ready && $0.blockedUntil == nil },
                candidates.filter { $0.resetsAt != nil }.min { $0.resetsAt! < $1.resetsAt! },
                candidates.first { ($0.blockedUntil ?? .distantPast) > now })
    }

    static func make(ready: WindowStatus?, soonest: WindowStatus?, blocked: WindowStatus?, runsOutAt: Date?,
                     signedOut: Bool, now: Date) -> MenuBarGlance? {
        // A weekly limit outranks everything: no countdown or "ready" would be true until it lifts.
        if let b = blocked, let until = b.blockedUntil, until > now {
            return MenuBarGlance(tone: .blocked, text: prefix(b) + Fmt.when(until, now: now),
                                 spoken: "\(spokenName(b)): weekly limit used up until \(Fmt.when(until, now: now))")
        }
        if let r = ready {
            return MenuBarGlance(tone: .ready, text: prefix(r) + "ready", spoken: "\(spokenName(r)): a fresh window is ready")
        }
        guard let s = soonest, let reset = s.resetsAt else { return nil }
        let countdown = prefix(s) + Fmt.short(reset.timeIntervalSince(now))
        let warn = signedOut && s.id == "claude"
        let lead = (warn ? "Claude Code is signed out. " : "") + spokenName(s) + ": "
        let until = "\(words(reset.timeIntervalSince(now))) until the reset"
        // The forecast is Claude's, and only counts when it lands before this window's reset. Then what's left and
        // when it runs out matter more than the reset countdown, and a countdown next to a clock time ("4:42 · out
        // 9:29") read as two clock times; so it's "86% · out 9:29", and the reset time is a click away in the menu.
        if s.id == "claude", let out = runsOutAt, out > now, out < reset {
            let first = s.usedPercent.map { "\(Int(max(0, 100 - $0).rounded()))%" } ?? countdown
            let left = s.usedPercent.map { "\(Int(max(0, 100 - $0).rounded())) percent left, but" } ?? "\(until), but"
            return MenuBarGlance(tone: .runningOut, text: "\(first) · out \(shortClock.string(from: out))", warning: warn,
                                 spoken: lead + "\(left) at this pace it runs out at \(Fmt.clock.string(from: out)), before the reset")
        }
        guard let used = s.usedPercent else {
            // No usage reading: the countdown alone, rather than a percentage that would really be the clock.
            return MenuBarGlance(tone: .normal, text: countdown, warning: warn, spoken: lead + until)
        }
        let left = max(0, 100 - used)
        let low = left <= lowPercent
        return MenuBarGlance(tone: low ? .low : .normal, text: "\(countdown) · \(Int(left.rounded()))%", warning: warn,
                             spoken: lead + "\(until), \(Int(left.rounded())) percent left" + (low ? ", almost empty" : ""))
    }

    /// "Claude" or "Claude Team", without the dot that VoiceOver would read as "dot".
    private static func spokenName(_ s: WindowStatus) -> String {
        s.name.replacingOccurrences(of: " · ", with: " ")
    }

    /// "2 hours 46 minutes", "1 hour", "12 minutes", "less than a minute".
    static func words(_ interval: TimeInterval) -> String {
        let m = max(0, Int(interval / 60)), h = m / 60, r = m % 60
        func unit(_ n: Int, _ w: String) -> String { "\(n) \(w)\(n == 1 ? "" : "s")" }
        if h == 0 { return r == 0 ? "less than a minute" : unit(r, "minute") }
        return r == 0 ? unit(h, "hour") : "\(unit(h, "hour")) \(unit(r, "minute"))"
    }

    /// "6:40" without AM/PM: the run-out time is always within the next five hours, and the pill stays narrow.
    private static let shortClock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm"; return f }()

    /// Claude needs no letter (it's what Reset is mostly for); other tools get theirs so it's clear whose window it is.
    private static func prefix(_ s: WindowStatus) -> String {
        if s.id == "claude" { return "" }
        // A second Claude account is named by its plan ("Claude · Pro" → "Pro"); "C" would read as Codex.
        if s.id.hasPrefix("claude-"), let label = s.name.components(separatedBy: " · ").last { return label + " " }
        return "\(s.name.prefix(1)) "
    }
}

/// The pill itself, drawn as an image: menu bar labels are plain text unless they're an image, and the image
/// must not be a template or macOS would paint it in one colour.
enum MenuBarPill {
    static func colors(_ tone: MenuBarGlance.Tone) -> (fill: Color, ink: Color) {
        switch tone {
        case .normal: return (Color(red: 1, green: 0.62, blue: 0.26), .black)
        case .low, .runningOut: return (Color(red: 1, green: 0.3, blue: 0.28), .white)
        case .ready: return (Color(red: 0.3, green: 0.85, blue: 0.42), .black)
        case .blocked: return (.clear, .primary)
        }
    }

    @MainActor static func image(_ g: MenuBarGlance) -> NSImage? {
        let (fill, ink) = colors(g.tone)
        let view = HStack(spacing: 3) {
            if g.warning { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9.5, weight: .bold)) }
            Text(g.text).font(.system(size: 12, weight: .semibold).monospacedDigit())
        }
        .foregroundColor(ink)
        .padding(.horizontal, 7)
        .frame(height: 17)
        .background(Capsule().fill(fill))
        .fixedSize()
        let r = ImageRenderer(content: view)
        r.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let img = r.nsImage else { return nil }
        img.isTemplate = false
        return img
    }
}
