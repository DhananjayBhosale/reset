import SwiftUI
import WidgetKit

// MARK: Fuse (medium): where the current pace runs out, before or after the reset

struct FuseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reset.fuse", provider: Provider()) { e in Fuse(e: e) }
            .configurationDisplayName("Fuse")
            .description("Your window as a burning fuse: where today's pace runs out, and how much to slow down to make the reset.")
            .supportedFamilies([.systemMedium])
    }
}

struct Fuse: View {
    let e: Entry
    private static let red = Color(red: 1, green: 0.33, blue: 0.3)
    private static let amber = Color(red: 1, green: 0.62, blue: 0.26)
    private static let ash = Color.white.opacity(0.16)

    var body: some View {
        let p = e.snap?.claude
        let m = FuseModel.make(p, runsOutAt: e.snap?.claudeRunsOutAt, now: e.date)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                if let p, let img = W.mascot("claude", p, at: e.date) {
                    img.resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline(m)).font(.system(size: 21, weight: .semibold).monospacedDigit())
                        .foregroundStyle(m.state == .runningOut ? Self.red : .white).lineLimit(1).minimumScaleFactor(0.7)
                    Text(detail(m)).font(.system(size: 11)).foregroundStyle(W.dim).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 4)
            fuse(m).frame(height: 44)
            HStack {
                Text(m.start.map(time) ?? " ").font(.system(size: 10)).foregroundStyle(W.dim)
                Spacer()
                Text(m.reset.map { "reset " + time($0) } ?? " ").font(.system(size: 10)).foregroundStyle(W.dim)
            }
            .padding(.top, 2)
        }
        .containerBackground(for: .widget) { Color(red: 0.07, green: 0.07, blue: 0.08) }
    }

    // MARK: Words

    private func headline(_ m: FuseModel) -> String {
        switch m.state {
        case .unknown: return "Open Reset"
        case .ready: return "Fuse not lit"
        case .blocked(let until): return "Weekly limit until \(time(until))"
        case .onPace: return m.percentLeft.map { "On pace · \($0)% left" } ?? "On pace"
        case .runningOut: return "Runs out \(m.runsOutAt.map(time) ?? "")"
        }
    }

    private func detail(_ m: FuseModel) -> String {
        switch m.state {
        case .unknown: return "No usage yet"
        case .ready: return "A fresh window is waiting. Your next message lights it."
        case .blocked: return "A new session window wouldn't help until then."
        case .onPace: return m.reset.map { "Lasts until the \(time($0)) reset at this pace" } ?? ""
        case .runningOut:
            guard let out = m.runsOutAt, let reset = m.reset else { return "" }
            let early = duration(reset.timeIntervalSince(out))
            return "\(early) before the reset" + (m.slowDownPercent.map { " · slow down \($0)% to make it" } ?? "")
        }
    }

    private func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    private func duration(_ s: TimeInterval) -> String {
        let m = max(0, Int(s / 60)), h = m / 60
        return h > 0 ? "\(h)h \(m % 60)m" : "\(m)m"
    }

    // MARK: The fuse

    /// Burnt rope to the left of the spark, fresh rope to the right, a red flag where the pace runs out,
    /// and a marker at the reset. Unlit and grey when no window is running.
    private func fuse(_ m: FuseModel) -> some View {
        GeometryReader { g in
            let w = g.size.width, y = g.size.height * 0.68
            let lit = m.state == .onPace || m.state == .runningOut
            let x = w * m.progress
            ZStack(alignment: .topLeading) {
                // Rope: short segments read as braided cord at widget size.
                HStack(spacing: 2) {
                    ForEach(0..<34, id: \.self) { i in
                        let f = (Double(i) + 0.5) / 34
                        Capsule().fill(rope(f, m: m, lit: lit)).frame(height: 7)
                    }
                }
                .frame(width: w).offset(y: y - 3.5)

                if let r = m.runOutProgress {
                    flag(at: w * r, y: y, label: m.runsOutAt.map(time) ?? "")
                }
                // Reset marker at the end of the fuse.
                Capsule().fill(Color.white.opacity(0.7)).frame(width: 2.5, height: 18).offset(x: w - 1.25, y: y - 9)

                if lit {
                    spark().offset(x: x - 15, y: y - 15)
                }
            }
        }
    }

    private func rope(_ f: Double, m: FuseModel, lit: Bool) -> Color {
        guard lit else { return Self.ash }
        if f < m.progress { return Self.ash }                                   // already burned
        if let r = m.runOutProgress, f > r { return Self.red.opacity(0.45) }   // past the run-out point
        return Self.amber
    }

    private func flag(at x: CGFloat, y: CGFloat, label: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Self.red))
                .fixedSize()
            Rectangle().fill(Self.red).frame(width: 2, height: 10)
        }
        .frame(width: 70)
        .offset(x: x - 35, y: y - 31)
    }

    private func spark() -> some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color.white, Color.yellow.opacity(0.95), Self.amber.opacity(0.55), .clear],
                                         center: .center, startRadius: 0, endRadius: 15))
            Image(systemName: "sparkle").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
    }
}
