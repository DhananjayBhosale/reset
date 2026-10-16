import CoreImage.CIFilterBuiltins
import SwiftUI

/// First-run setup: the five things that make Reset useful, in about a minute.
struct OnboardingView: View {
    @Bindable var store: Store
    var onFinish: () -> Void

    init(store: Store, startAt: Step = .welcome, onFinish: @escaping () -> Void) {
        self.store = store
        self.onFinish = onFinish
        _step = State(initialValue: startAt)
    }

    enum Step: Int, CaseIterable { case welcome, tools, claude, phone, extras, done }
    @State private var step: Step
    @State private var detected: Set<String> = []
    @State private var chosen: Set<String> = []
    @State private var cli: ClaudeCLI.Status?
    @State private var signingIn = false
    @State private var testSent = false

    private let names = [("claude", "Claude Code"), ("codex", "Codex"), ("gemini", "Gemini CLI"), ("antigravity", "Antigravity")]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .welcome: welcome
                case .tools: tools
                case .claude: claude
                case .phone: phone
                case .extras: extras
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(32)
            .transition(.opacity)
            footer
        }
        .frame(width: 620, height: 560)
        .background(
            ZStack {
                Color.black
                RadialGradient(colors: [Color(hex: 0xFF8A2A).opacity(0.28), .clear], center: UnitPoint(x: 0.5, y: 1.1), startRadius: 0, endRadius: 420)
            }
        )
        .environment(\.colorScheme, .dark)
        .onAppear {
            detected = InstalledTools.detect()
            // Run again from Settings, start from what's on now: starting from detection switched off any tool the
            // user had turned on by hand, and its auto-start with it, as soon as they pressed Continue.
            let on = Set(names.map(\.0).filter { store.prefs(for: $0).enabled })
            if UserDefaults.standard.bool(forKey: "onboarded"), !on.isEmpty { chosen = on }
            else { chosen = detected.isEmpty ? ["claude"] : detected }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: -12) {
                ForEach(["claude", "codex", "gemini", "antigravity"], id: \.self) { id in
                    if let img = MascotArt.image(id, .fresh) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: 92, height: 92)
                    }
                }
            }
            .padding(.bottom, 6)
            Text("Welcome to Reset").font(.system(size: 30, weight: .semibold))
            Text("Reset tells you when your AI usage window resets, pings your phone when it does, and shows what your usage is worth.")
                .font(.system(size: 15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                bullet("clock", "A countdown to your next window, in the menu bar")
                bullet("iphone", "Phone alerts that arrive even while your Mac sleeps")
                bullet("chart.bar", "A dashboard, widgets and a card you can share")
                bullet("lock", "Everything it reads stays on this Mac")
            }
            .padding(.top, 6)
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Which tools do you use?", "Reset found the ones with a tick. You can change this later in Settings.")
            ForEach(names, id: \.0) { id, name in
                Button {
                    if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) }
                } label: {
                    HStack(spacing: 14) {
                        if let img = MascotArt.image(id, .fresh) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.system(size: 14, weight: .medium))
                            Text(detected.contains(id) ? "Found on this Mac" : "Not found").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: chosen.contains(id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20)).foregroundStyle(chosen.contains(id) ? Theme.color(for: id) : Color.secondary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(chosen.contains(id) ? 0.08 : 0.03)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var claude: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Exact Claude usage", "With this on, Reset shows your real usage % and the exact reset time instead of an estimate. It asks Anthropic every 2 minutes while you're using Claude Code (every 5 minutes otherwise) with Claude Code's own sign-in, and sends it nowhere else.")
            HStack(spacing: 12) {
                Image(systemName: cliIcon).font(.system(size: 22)).foregroundStyle(cliColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cliTitle).font(.system(size: 14, weight: .medium))
                    Text(cliDetail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if cli?.installed == true && cli?.signedIn == false {
                    Button(signingIn ? "Waiting for browser…" : "Sign in") {
                        signingIn = true
                        ClaudeCLI.signIn { _ in
                            signingIn = false
                            ClaudeCLI.status { cli = $0; if $0.signedIn { store.liveClaudeEnabled = true } }
                        }
                    }
                    .disabled(signingIn)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
            Toggle("Use live usage from my Claude account", isOn: $store.liveClaudeEnabled)
                .disabled(cli?.signedIn != true)
            if store.liveClaudeEnabled {
                HStack(spacing: 8) {
                    if case .ok = store.liveClaude.state, let c = store.statuses.first(where: { $0.id == "claude" }), let u = c.usedPercent {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("Working: \(Int(u.rounded()))% of your window used\(c.resetsAt.map { ", resets \(Fmt.clock.string(from: $0))" } ?? "")")
                    } else if case .problem(let why) = store.liveClaude.state {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(why)
                    } else {
                        ProgressView().controlSize(.small)
                        Text("Checking…")
                    }
                }
                .font(.system(size: 12))
            }
        }
        .onAppear { ClaudeCLI.status { cli = $0 } }
    }

    private var phone: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Alerts on your phone", "Reset uses ntfy, a free open source notification app. Alerts are queued on the ntfy server ahead of time, so they reach you even when this Mac is asleep.")
            Toggle("Send reset alerts to my phone", isOn: Binding(get: { store.phoneEnabled }, set: { v in
                if v && store.ntfyTopic.isEmpty { store.ntfyTopic = Self.newTopic() }
                store.phoneEnabled = v
            }))
            if store.phoneEnabled, let url = URL(string: "\(store.ntfyServer)/\(store.ntfyTopic)") {
                HStack(alignment: .top, spacing: 20) {
                    if let qr = Self.qr(url.absoluteString) {
                        Image(nsImage: qr).interpolation(.none).resizable().frame(width: 150, height: 150)
                            .padding(8).background(RoundedRectangle(cornerRadius: 12).fill(.white))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        step(1, "Install the free ntfy app from the App Store or Google Play.")
                        step(2, "Scan the code with your phone's camera, or add this topic in the app:")
                        Text(store.ntfyTopic).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            .padding(.horizontal, 8).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                        step(3, "Send a test to check it arrives.")
                        Button(testSent ? "Sent, check your phone" : "Send test") { store.sendTestPush(); testSent = true }
                        Text("Anyone who knows the topic can read your alerts, so keep it private.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("A few extras", "All optional. Everything here is in Settings too.")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What you pay per month").font(.system(size: 14, weight: .medium))
                    Text("Shows how much API value your plan gets you, like 13.7×.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("$")
                TextField("0", value: Binding(get: { store.usage.planMonthlyUSD }, set: { store.usage.planMonthlyUSD = $0 }), format: .number).frame(width: 80).textFieldStyle(.roundedBorder)
            }
            if chosen.contains("claude") {
                Toggle(isOn: Binding(get: { store.prefs(for: "claude").autoStart }, set: { v in store.setPrefs("claude") { $0.autoStart = v } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start the next window automatically").font(.system(size: 14, weight: .medium))
                        Text("When a window runs out, Reset sends Claude a one-word message so the next one starts right away. Uses a little quota each time.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep this Mac awake").font(.system(size: 14, weight: .medium))
                    Text("So auto-start and alerts run on time overnight. The display still sleeps.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: Binding(get: { store.keepAwake.mode }, set: { store.keepAwake.mode = $0 })) {
                    ForEach(KeepAwake.Mode.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 170)
            }
            Toggle(isOn: Binding(get: { store.mascots.enabled }, set: { store.mascots.enabled = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Desktop mascots").font(.system(size: 14, weight: .medium))
                    Text("Little characters whose mood follows your usage. Unofficial fan art.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 })) {
                Text("Open Reset when I log in").font(.system(size: 14, weight: .medium))
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let img = MascotArt.image("claude", .waking) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: 130, height: 130)
            }
            Text("You're set").font(.system(size: 30, weight: .semibold))
            Text("Reset is in your menu bar. Click the countdown for the quick panel, or open the dashboard for the full picture.")
                .font(.system(size: 15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                bullet("rectangle.grid.2x2", "Add widgets: right-click your desktop, choose Edit Widgets, search Reset")
                bullet("square.and.arrow.up", "Share your month from the dashboard's Share card button")
                bullet("gearshape", "Change anything later in Settings, or run this setup again")
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule().fill(s == step ? Color.white : Color.white.opacity(0.2)).frame(width: s == step ? 18 : 6, height: 6)
                }
            }
            Spacer()
            if step != .welcome && step != .done {
                Button("Back") { go(-1) }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.trailing, 10)
            }
            Button(action: next) {
                Text(step == .done ? "Open dashboard" : step == .welcome ? "Get started" : "Continue")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 32).padding(.vertical, 18)
        .background(Color.white.opacity(0.03))
    }

    private func next() {
        if step == .tools {
            for (id, _) in names { store.setPrefs(id) { $0.enabled = chosen.contains(id); if !chosen.contains(id) { $0.autoStart = false } } }
        }
        if step == .done { onFinish(); return }
        go(1)
    }

    /// Moves between steps, skipping the Claude step when Claude isn't one of the chosen tools.
    private func go(_ d: Int) {
        var i = step.rawValue + d
        if Step(rawValue: i) == .claude && !chosen.contains("claude") { i += d }
        withAnimation(.easeInOut(duration: 0.2)) { step = Step(rawValue: max(0, min(Step.allCases.count - 1, i))) ?? step }
    }

    // MARK: Pieces

    private func header(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 24, weight: .semibold))
            Text(sub).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(Theme.accent)
            Text(text).font(.system(size: 14))
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.system(size: 11, weight: .bold)).frame(width: 18, height: 18).background(Circle().fill(Color.white.opacity(0.15)))
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cliIcon: String { cli == nil ? "hourglass" : cli!.signedIn ? "checkmark.circle.fill" : cli!.installed ? "person.crop.circle.badge.exclamationmark" : "xmark.circle" }
    private var cliColor: Color { cli?.signedIn == true ? .green : cli?.installed == true ? .orange : .secondary }
    private var cliTitle: String {
        guard let c = cli else { return "Checking Claude Code…" }
        if c.signedIn { return "Claude Code is signed in" + (c.plan.map { " (\($0.capitalized) plan)" } ?? "") }
        return c.installed ? "Claude Code is signed out" : "Claude Code isn't installed"
    }
    private var cliDetail: String {
        guard let c = cli else { return " " }
        if c.signedIn { return "Live usage and auto-start can use it." }
        return c.installed ? "Sign in once and Reset can read your exact usage. Your browser will open."
                           : "Install it from claude.com/code to get exact usage. Reset still estimates from your activity."
    }

    static func newTopic() -> String {
        let chars = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return "reset-" + String((0..<16).map { _ in chars.randomElement()! })
    }

    static func qr(_ s: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}
