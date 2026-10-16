import SwiftUI

/// The dashboard's hero card: the Claude session window, its countdown and arc, the limit used and any pacing
/// budget. Plain inputs instead of the live store, so a snapshot test can draw it with fixed numbers at
/// different widths (it once had an arc running through the countdown on narrow windows).
struct HeroCard: View {
    var status: WindowStatus?
    var now: Date
    var subtitle: String
    var signedOut = false
    var signingIn = false
    var runsOutAt: Date?
    var budget: Budget?
    var budgetUsed: Double?
    var onSignIn: () -> Void = {}
    var onClearBudget: () -> Void = {}

    var body: some View {
        GlowCard(glow: Color(hex: 0xFF8A2A), glowAt: UnitPoint(x: 0.5, y: 0.55), glowSize: 300, glowOpacity: 0.6) {
            let c = status
            let end = c?.resetsAt
            let remaining = end.map { max(0, $0.timeIntervalSince(now)) } ?? 0
            let elapsed = end != nil ? 1 - remaining / (5 * 3600) : 0
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        CardHeader(title: "Claude session window", subtitle: subtitle)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(end.map { Fmt.clock.string(from: $0) } ?? "--").font(Dash.num(15)).foregroundStyle(.white)
                            Text(end == nil ? "no window running" : "resets").font(Dash.label).foregroundStyle(Dash.dim)
                        }
                    }
                    Spacer(minLength: 0)
                    // The arc shares a row with the countdown, so the layout keeps them apart at any window width;
                    // drawn behind the whole card it ran through the digits when the window was narrow.
                    HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if c?.state == .ready {
                            Text("Ready").font(Dash.hero(84)).foregroundStyle(.white)
                        } else {
                            let h = Int(remaining) / 3600, m = (Int(remaining) % 3600) / 60
                            Text(h > 0 ? "\(h)h \(m)" : "\(m)").font(Dash.hero(92)).foregroundStyle(.white)
                            Text("m").font(Dash.hero(28)).foregroundStyle(Dash.dim)
                        }
                    }
                    Group {
                        if signedOut {
                            HStack(spacing: 6) {
                                Text("Live usage paused: Claude Code is signed out.").foregroundStyle(Color(hex: 0xFFB13D))
                                Button(signingIn ? "Waiting for browser…" : "Sign in") { onSignIn() }
                                    .buttonStyle(.plain).foregroundStyle(.white).underline()
                            }
                        } else if let out = runsOutAt, c?.state != .ready {
                            Text("at this pace you run out around \(Fmt.clock.string(from: out))").foregroundStyle(Color(hex: 0xFF8A5C))
                        } else {
                            Text(c?.state == .ready ? "send a message to start the clock" : "until a fresh window").foregroundStyle(Dash.dim)
                        }
                    }
                    .font(Dash.label)
                    }
                    .layoutPriority(1)
                    // Decorative: the countdown beside it says the same in words.
                    WindowArc(progress: elapsed, color: Dash.claude)
                        .accessibilityHidden(true)
                        .frame(minWidth: 110, maxWidth: 280)
                        .frame(height: 140)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.bottom, 18)
                    HStack {
                        Text("Limit used").font(Dash.label).foregroundStyle(Dash.dim)
                        Spacer()
                        Text(c?.usedPercent.map { "\(Int($0.rounded()))%" } ?? "unknown").font(Dash.num(14)).foregroundStyle(Dash.claude)
                    }
                    .padding(.bottom, 8)
                    BurnBar(fraction: (c?.usedPercent ?? 0) / 100)
                        .accessibilityElement()
                        .accessibilityLabel("Limit used")
                        .accessibilityValue(c?.usedPercent.map { "\(Int($0.rounded())) percent" } ?? "unknown")
                        .overlay(alignment: .leading) {
                            // Where the budget's cap sits on the bar, so the line below has a place to point at.
                            if let b = budget {
                                GeometryReader { g in
                                    Capsule().fill(.white.opacity(0.85))
                                        .frame(width: 2, height: 18)
                                        .offset(x: g.size.width * CGFloat(b.maxPercent) / 100 - 1, y: -3)
                                }
                            }
                        }
                    if let b = budget { budgetLine(b, used: budgetUsed) }
                }
            }
            .frame(height: 312)
        }
    }


    /// The pacing budget an agent set through reset-mcp: task, cap, where it stands, and a way to clear it,
    /// because a budget nobody clears would otherwise steer every later session.
    private func budgetLine(_ b: Budget, used: Double?) -> some View {
        let status = b.status(used: used)
        let (word, color): (String, Color) = {
            switch status {
            case .normal: return ("on pace", Dash.dim)
            case .wrapUp: return ("wrap up", Color(hex: 0xFFB13D))
            case .over: return (b.downshiftModel.map { "over, switch to \($0)" } ?? "over, stop", Color(hex: 0xFF5C3A))
            case .unknown: return ("usage unknown", Dash.dim)
            }
        }()
        return HStack(spacing: 6) {
            Text("BUDGET").foregroundStyle(Dash.dim)
            Text(b.task).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
            Text("cap \(b.maxPercent)%").foregroundStyle(Dash.dim)
            Text(word).foregroundStyle(color)
            Spacer(minLength: 8)
            Button { onClearBudget() } label: {
                HStack(spacing: 3) { Image(systemName: "xmark"); Text("Clear") }
            }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
            .help("Remove this budget. Agents stop getting wrap-up and downshift advice for it.")
        }
        .font(Dash.label)
        .padding(.top, 8)
        .help(b.advice(used: used))
    }
}
