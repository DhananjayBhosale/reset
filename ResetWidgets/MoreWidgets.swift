import SwiftUI
import WidgetKit

struct MoreWidgets: WidgetBundle {
    var body: some Widget {
        GaugeSmallWidget()
    }
}

private func claudeCard(_ e: Entry) -> CardData? {
    guard let p = e.snap?.claude else { return nil }
    return CardData(id: p.id, name: p.name, color: W.color(p.id), windowStart: p.resetsAt?.addingTimeInterval(-5 * 3600),
                    resetsAt: p.resetsAt, ready: p.ready, blockedUntil: p.blockedUntil, used: p.used,
                    mascot: W.mascot(p.id, p, at: e.date), estimate: p.estimate)
}

private struct Missing: View {
    var body: some View { Text("Open Reset").font(.system(size: 12)).foregroundStyle(W.dim) }
}

// MARK: Gauge (small)

struct GaugeSmallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.small.gauge", provider: Provider()) { e in GaugeSmall(e: e) }
            .configurationDisplayName("Gauge")
            .description("A watch-style gauge of Claude's window left.")
            .supportedFamilies([.systemSmall])
    }
}

struct GaugeSmall: View {
    let e: Entry
    var body: some View {
        Group {
            if let d = claudeCard(e) {
                let left = d.left(at: e.date) ?? 1
                ZStack {
                    // The tick marks are drawing only; the number in the middle is what VoiceOver reads.
                    Canvas { ctx, size in
                        let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2 - 2
                        let n = 48
                        for i in 0..<n {
                            let f = Double(i) / Double(n - 1)
                            let a = (-225 + 270 * f) * .pi / 180
                            var p = Path()
                            p.move(to: CGPoint(x: c.x + cos(a) * (r - 12), y: c.y + sin(a) * (r - 12)))
                            p.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                            let lit = f <= left
                            ctx.stroke(p, with: .color(lit ? (left > 0.2 ? Color(red: 0.96, green: 0.62, blue: 0.04) : .red) : .white.opacity(0.12)),
                                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        }
                    }
                    .accessibilityHidden(true)
                    VStack(spacing: 0) {
                        // "~" and "time left" when it's the clock rather than a usage reading; "est." when guessed.
                        Text((d.usageKnown || d.isReady(at: e.date) ? "" : "~") + "\(Int((left * 100).rounded()))%")
                            .font(.system(size: 30, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                        Text(d.leftWord(at: e.date) + (d.estimate != nil ? " · est." : "")).font(.system(size: 10)).foregroundStyle(W.dim)
                        CountdownText(d: d, now: e.date, align: .center).font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.26)).padding(.top, 4)
                            .frame(width: 76)
                            .environment(\.lookUsesTimerText, true)
                    }
                }
            } else { Missing() }
        }
        .containerBackground(for: .widget) { Color(red: 0.07, green: 0.07, blue: 0.075) }
    }
}
