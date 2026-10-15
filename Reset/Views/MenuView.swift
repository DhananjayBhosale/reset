import SwiftUI

struct MenuView: View {
    @Bindable var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MicroLabel("Reset")
                Spacer()
                Text(Fmt.clock.string(from: store.now)).font(Theme.mono(10)).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Hairline()

            if store.visible.isEmpty {
                Text("No providers switched on. Open Settings.")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim).padding(14)
            }
            ForEach(store.visible) { s in
                ProviderRow(store: store, status: s)
                Hairline()
            }

            if let last = store.log.first {
                Text(last).font(Theme.mono(9, .regular)).foregroundStyle(Theme.dim).lineLimit(2)
                    .padding(.horizontal, 14).padding(.top, 8)
            }

            HStack(spacing: 8) {
                LineButton("Dashboard", color: Theme.accent) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "dashboard")
                }
                LineButton("Settings") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }
                LineButton("Rescan") { store.refresh() }
                LineButton("Pets", color: store.mascots.enabled ? Theme.text : Theme.dim) { store.mascots.enabled.toggle() }
                Spacer()
                LineButton("Quit", color: Theme.dim) { NSApp.terminate(nil) }
            }
            .padding(14)
        }
        .frame(width: 380)
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
    }
}

struct ProviderRow: View {
    let store: Store
    let status: WindowStatus

    private var color: Color { Theme.color(for: status.id) }
    private var prefs: ProviderPrefs { store.prefs(for: status.id) }

    var body: some View {
        if store.look == .mono { monoRow } else {
            VStack(alignment: .leading, spacing: 6) {
                LookCard(look: store.look, d: store.cardData(for: status), now: store.now)
                    .frame(height: 128)
                if status.id == "claude", let out = store.forecast.runsOutAt {
                    Text("At this pace you run out around \(Fmt.clock.string(from: out))")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Color(hex: 0xFF8A5C))
                }
                if let sec = status.secondary {
                    Text("\(sec.label)  resets \(Fmt.when(sec.resetsAt, now: store.now))\(sec.usedPercent.map { "  ·  \(Int($0.rounded()))% used" } ?? "")")
                        .font(.system(size: 10)).foregroundStyle(Theme.dim)
                }
                actions
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .help(status.source)
        }
    }

    private var monoRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(color).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                Text(status.name.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Theme.text)
                if status.isEstimate { Tag("est") }
                if prefs.autoStart && status.canAutoStart { Tag("auto", color: color) }
                Spacer()
                countdown
            }
            HStack {
                Text(detail).font(Theme.mono(10, .regular)).foregroundStyle(Theme.dim)
                Spacer()
                if let u = status.usedPercent { Text("\(Int(u.rounded()))% used").font(Theme.mono(10, .regular)).foregroundStyle(Theme.dim) }
            }
            if let u = status.usedPercent { Meter(fraction: u / 100, color: color) }
            if let sec = status.secondary {
                HStack {
                    Text("\(sec.label.uppercased())  resets \(Fmt.when(sec.resetsAt, now: store.now))")
                        .font(Theme.mono(9, .regular)).foregroundStyle(Theme.dim)
                    Spacer()
                    if let u = sec.usedPercent { Text("\(Int(u.rounded()))%").font(Theme.mono(9, .regular)).foregroundStyle(Theme.dim) }
                }
            }
            actions
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .help(status.source)
    }

    @ViewBuilder private var countdown: some View {
        switch status.state {
        case .active(let at):
            Text(Fmt.countdown(at.timeIntervalSince(store.now))).font(Theme.mono(18)).foregroundStyle(Theme.text)
                .monospacedDigit()
        case .ready:
            Text("READY").font(Theme.mono(13, .regular)).foregroundStyle(color)
        case .unavailable:
            Text("--").font(Theme.mono(13)).foregroundStyle(Theme.dim)
        }
    }

    private var detail: String {
        switch status.state {
        case .active(let at): return "resets \(Fmt.when(at, now: store.now))"
        case .ready: return "next message starts a window"
        case .unavailable(let why): return why
        }
    }

    @ViewBuilder private var actions: some View {
        let isCustom = status.id.hasPrefix("custom-")
        if status.id == "claude" || isCustom || (status.canAutoStart && status.state == .ready) {
            HStack(spacing: 6) {
                if status.id == "claude" {
                    LineButton("Used on web", color: color) { store.markClaudeUsedElsewhere() }
                        .help("Tell Reset you just used Claude outside Claude Code, so it can start the clock")
                }
                if isCustom {
                    LineButton("Started now", color: color) { store.startCustom(status.id) }
                    if status.resetsAt != nil { LineButton("Clear", color: Theme.dim) { store.clearCustom(status.id) } }
                }
                if status.canAutoStart && status.state == .ready && store.commands[status.id]?.isEmpty == false {
                    LineButton("Start window", color: color) { store.kickNow(status.id) }
                        .help("Runs: \(store.commands[status.id] ?? "")")
                }
            }
            .padding(.top, 2)
        }
    }
}

struct Tag: View {
    let text: String
    var color: Color = Theme.dim
    init(_ text: String, color: Color = Theme.dim) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 8, weight: .medium)).tracking(1)
            .foregroundStyle(color).padding(.horizontal, 4).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(color.opacity(0.5), lineWidth: 1))
    }
}

struct Meter: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.hairline)
                Rectangle().fill(color).frame(width: g.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 2)
    }
}
