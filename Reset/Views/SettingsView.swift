import SwiftUI

struct SettingsView: View {
    @Bindable var store: Store
    @State private var newName = ""
    @State private var newHours = 5.0
    @State private var topicDraft = ""
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var m = store.mascots
        Form {
            // Only shown when something is wrong; a healthy check is one quiet line under About.
            if [.problems, .noRows].contains(store.usage.format.verdict) {
                Section {
                    Label {
                        Text(store.usage.format.summary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    HStack {
                        Button(store.updater.checking ? "Checking…" : "Check for a Reset update") { store.updater.check() }
                            .disabled(store.updater.checking)
                        Link("Report it on GitHub", destination: URL(string: ResetInfo.repoURL + "/issues")!)
                    }
                } header: {
                    Text("Claude Code log format")
                } footer: {
                    Text("Reset reads Claude Code's local logs, and a Claude Code update can change how they're written. Nothing is sent anywhere by this check.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Providers") {
                ForEach(builtIns, id: \.0) { id, name in
                    providerRow(id: id, name: name)
                }
            }

            Section {
                ForEach(store.custom) { c in
                    HStack {
                        Text(c.name)
                        Text("\(c.windowHours, specifier: "%g")h window").foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Alert", isOn: binding("custom-" + c.id, \.alert)).toggleStyle(.checkbox)
                        Button(role: .destructive) { store.custom.removeAll { $0.id == c.id } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Name, e.g. ChatGPT", text: $newName)
                    Stepper("\(newHours, specifier: "%g")h", value: $newHours, in: 0.5...168, step: 0.5)
                        .frame(width: 110)
                    Button("Add") {
                        store.custom.append(CustomProvider(name: newName.trimmingCharacters(in: .whitespaces),
                                                           windowHours: newHours))
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Other tools")
            } footer: {
                Text("For tools Reset cannot read on its own. Press Started now in the menu when you begin, and Reset counts down the window.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 14) {
                    ForEach(Look.allCases) { look in
                        Button { store.look = look } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                LookCard(look: look, d: sampleCard, now: store.now)
                                    .frame(width: 340, height: 128)
                                    .scaleEffect(0.62, anchor: .topLeading)
                                    .frame(width: 211, height: 80, alignment: .topLeading)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(store.look == look ? Color.accentColor : .clear, lineWidth: 2.5))
                                Text(look.name).font(.system(size: 12, weight: store.look == look ? .semibold : .regular))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Look")
            } footer: {
                Text("How each provider is drawn in the menu.").foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show mascots", isOn: $m.enabled)
                Picker("Where they live", selection: $m.placement) {
                    ForEach(Placement.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!store.mascots.enabled)
                HStack {
                    Text("Size")
                    Slider(value: $m.size, in: 56...140, step: 4)
                }
                .disabled(!store.mascots.enabled)
                ForEach(MascotArt.providers.filter { id in store.statuses.contains { $0.id == id } }, id: \.self) { id in
                    Toggle(store.statuses.first { $0.id == id }?.name ?? id, isOn: Binding(
                        get: { !store.mascots.hidden.contains(id) },
                        set: { v in if v { store.mascots.hidden.remove(id) } else { store.mascots.hidden.insert(id) } }))
                        .toggleStyle(.checkbox)
                }
            } header: {
                Text("Mascots")
            } footer: {
                Text("Each mascot's mood and health bar follow how much of its window is left. Drag one to move it, right-click to change where they live. Mascots only show for providers switched on above.\n\nThe mascots are unofficial fan art based on the Claude, OpenAI, Gemini and Antigravity logos. Those names and logos belong to Anthropic, OpenAI and Google, who have nothing to do with Reset.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Heads-up before reset", selection: $store.leadMinutes) {
                    Text("Off").tag(0)
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
                }
            } header: {
                Text("Mac alerts")
            }

            Section {
                Toggle("Send reset alerts to my phone", isOn: $store.phoneEnabled)
                TextField("ntfy server", text: $store.ntfyServer)
                HStack {
                    TextField("Topic", text: $topicDraft, prompt: Text("a long random name only you know"))
                        .onSubmit { store.ntfyTopic = topicDraft }
                    Button("Save") { store.ntfyTopic = topicDraft }
                        .disabled(topicDraft == store.ntfyTopic || Alerts.endpoint(server: store.ntfyServer, topic: topicDraft) == nil)
                }
                HStack {
                    Button("Send test") { store.sendTestPush() }.disabled(store.ntfyTopic.isEmpty)
                    Spacer()
                    if Alerts.endpoint(server: store.ntfyServer, topic: topicDraft) == nil && !topicDraft.isEmpty {
                        Text("Letters, numbers, - and _ only").font(.caption).foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Phone alerts")
            } footer: {
                Text("Install the free ntfy app on your phone and subscribe to the same topic. Each alert is queued on the ntfy server with its delivery time, so it still arrives when this Mac is asleep, and it is replaced or withdrawn if the reset time changes. Alerts are sent at high priority; to break through Do Not Disturb, allow it for that priority in the ntfy app. Anyone who knows the topic name can read it, so pick something unguessable.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Keep this Mac awake", selection: Binding(get: { store.keepAwake.mode }, set: { store.keepAwake.mode = $0 })) {
                    ForEach(KeepAwake.Mode.allCases) { Text($0.label).tag($0) }
                }
                if store.keepAwake.mode != .off {
                    Text(store.keepAwake.isHolding ? "Keeping the Mac awake now." : "Not holding right now: the Mac is on battery.")
                        .font(.caption).foregroundStyle(store.keepAwake.isHolding ? Color.green : Color.secondary)
                }
            } header: {
                Text("Stay awake")
            } footer: {
                Text("Auto-start and on-time alerts need the Mac awake. This stops idle sleep only: the display still turns off as usual. Closing the lid still sleeps the Mac unless it's plugged in with an external display. Phone alerts arrive either way.")
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
            }

            Section("About") {
                Toggle("Check for updates automatically", isOn: Binding(get: { store.updater.automatic }, set: { store.updater.automatic = $0 }))
                HStack {
                    Text(updateText).foregroundStyle(store.updater.available == nil ? Color.secondary : Color.green)
                    Spacer()
                    if let u = store.updater.available {
                        Button("Download \(u.version)") { NSWorkspace.shared.open(u.url) }
                    } else {
                        Button(store.updater.checking ? "Checking…" : "Check now") { store.updater.check() }.disabled(store.updater.checking)
                    }
                }
                HStack {
                    Text("Setup")
                    Spacer()
                    Button("Run setup again") {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "welcome")
                    }
                }
                HStack {
                    Text("Reset \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    Spacer()
                    Link("Source on GitHub", destination: URL(string: ResetInfo.repoURL)!)
                }
                Text(store.usage.format.summary).font(.caption).foregroundStyle(.secondary)
                Text("Free and open source under the MIT license. Everything Reset reads stays on this Mac; the only things it sends out are the optional live Claude usage check (to Anthropic) and phone alerts (to the ntfy server you choose). Not affiliated with Anthropic, OpenAI or Google.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Activity") {
                if store.log.isEmpty { Text("Nothing yet").foregroundStyle(.secondary) }
                ForEach(Array(store.log.enumerated()), id: \.offset) { Text($0.element).font(.system(size: 11, design: .monospaced)) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 720)
        .onAppear { topicDraft = store.ntfyTopic }
    }

    private let builtIns = [("claude", "Claude"), ("codex", "Codex"), ("gemini", "Gemini CLI"), ("antigravity", "Antigravity")]

    @ViewBuilder private func providerRow(id: String, name: String) -> some View {
        let status = store.statuses.first { $0.id == id }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(name, isOn: binding(id, \.enabled))
                Spacer()
                Toggle("Alert", isOn: binding(id, \.alert)).toggleStyle(.checkbox)
                if status?.canAutoStart ?? (id != "gemini") {
                    Toggle("Auto-start", isOn: binding(id, \.autoStart)).toggleStyle(.checkbox)
                }
            }
            if let status { Text(status.source).font(.caption).foregroundStyle(.secondary) }
            if id == "claude" {
                Toggle("Live usage from your Claude account", isOn: $store.liveClaudeEnabled)
                Text("Exact % and reset time, every 3 minutes. Reads Claude Code's sign-in from your Keychain (macOS may ask once) and sends it only to api.anthropic.com. Usage numbers only, never chats.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.liveClaudeEnabled {
                    Text(liveText).font(.caption).foregroundStyle(liveIsProblem ? Color.orange : Color.secondary)
                }
            }
            if store.prefs(for: id).autoStart {
                TextField("Command", text: Binding(get: { store.commands[id] ?? "" },
                                                   set: { store.commands[id] = $0 }))
                    .font(.system(size: 11, design: .monospaced))
                Text("Runs once, two minutes after a window Reset was watching runs out, while the Mac is awake. Turning this on does not run it now. Skipped while a weekly limit is exhausted. Uses a little of your quota each time.")
                    .font(.caption).foregroundStyle(.secondary)
                if let last = store.kickLog.last(where: { $0.id == id }) {
                    HStack {
                        Text("Last auto-start \(Fmt.when(last.time)): \(last.summary)")
                            .font(.caption).foregroundStyle(last.ok ? Color.secondary : Color.orange)
                        if id == "claude", store.autoStartNeedsSignIn {
                            Spacer()
                            Button(store.signingIn ? "Waiting for browser…" : "Sign in") { store.fixClaudeSignIn() }
                                .controlSize(.small).disabled(store.signingIn)
                        }
                    }
                }
            }
        }
    }

    private var updateText: String {
        if let u = store.updater.available { return "Reset \(u.version) is available" }
        if let e = store.updater.lastError { return e }
        if let d = store.updater.lastChecked { return "Up to date, checked \(Fmt.clock.string(from: d))" }
        return "Version \(Updater.current)"
    }

    private var sampleCard: CardData {
        if let c = store.statuses.first(where: { $0.id == "claude" }) { return store.cardData(for: c) }
        return CardData(id: "claude", name: "Claude", color: Theme.color(for: "claude"), resetsAt: Date().addingTimeInterval(6000), ready: false, used: 58)
    }

    private var liveText: String {
        switch store.liveClaude.state {
        case .off, .loading: return "Connecting…"
        case .ok(let d): return "Live · updated \(Fmt.clock.string(from: d))"
        case .problem(let why): return why
        }
    }
    private var liveIsProblem: Bool { if case .problem = store.liveClaude.state { return true }; return false }

    private func binding(_ id: String, _ key: WritableKeyPath<ProviderPrefs, Bool>) -> Binding<Bool> {
        Binding(get: { store.prefs(for: id)[keyPath: key] },
                set: { v in store.setPrefs(id) { $0[keyPath: key] = v } })
    }
}
