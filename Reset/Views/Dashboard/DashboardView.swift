import SwiftUI

struct DashboardView: View {
    @Bindable var store: Store
    @Bindable var usage: UsageStore
    /// For rendering to an image: lay everything out at full height instead of scrolling.
    var flat = false
    @State private var editingPlan = false
    @State private var sharing = false
    @Environment(\.openWindow) private var openWindow

    private var claude: WindowStatus? { store.statuses.first { $0.id == "claude" } }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                sidebar
                Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1)
                scrolling {
                    VStack(spacing: 16) {
                        HStack(alignment: .top, spacing: 16) {
                            heroCard.frame(maxWidth: .infinity)
                            valueCard.frame(width: 360)
                        }
                        windowsCard
                        HStack(alignment: .top, spacing: 16) {
                            mixCard
                            heatCard
                        }
                        HStack(alignment: .top, spacing: 16) {
                            sessionsCard
                            sessionDetailCard
                        }
                        projectsCard
                    }
                    .padding(20)
                }
            }
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 1120, minHeight: 760)
        .onAppear {
            if usage.lastScan == nil { usage.refresh() }
            if usage.shareRequested { usage.shareRequested = false; sharing = true }
        }
        .onChange(of: usage.shareRequested) { _, v in if v { usage.shareRequested = false; sharing = true } }
    }

    @ViewBuilder private func scrolling<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        if flat { c() } else { ScrollView { c() } }
    }

    // MARK: Top bar

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 5 ? "Up late" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        let first = Demo.isOn ? "" : (NSFullUserName().split(separator: " ").first.map(String.init) ?? "")
        return first.isEmpty ? part + "." : "\(part), \(first)."
    }

    private var nextWindowLine: String {
        guard let c = claude else { return "" }
        if c.state == .ready { return "A fresh Claude window is ready." }
        if let r = c.resetsAt { return "Your next Claude window opens at \(Fmt.when(r, now: store.now))." }
        return ""
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            (Text(greeting + " ").foregroundColor(Dash.dim) + Text(nextWindowLine).foregroundColor(.white))
                .font(.system(size: 15))
            Spacer()
            HStack(spacing: 2) {
                ForEach(UsageRange.allCases) { r in
                    Button { usage.range = r } label: {
                        Text(r.rawValue).font(.system(size: 12))
                            .foregroundStyle(usage.range == r ? .white : Dash.dim)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(usage.range == r ? Color.white.opacity(0.1) : .clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.white.opacity(0.04)))
            if usage.loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    if usage.lastScan == nil {
                        Text(usage.filesRead > 0 ? "Reading your history · \(usage.filesRead) files" : "Reading your history…")
                            .font(.system(size: 12)).foregroundStyle(Dash.dim)
                    }
                }
            }
            Button { sharing = true } label: {
                Text("Share card").font(.system(size: 12, weight: .medium)).foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.92)))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $sharing) { ShareSheet(usage: usage) }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Providers").font(Dash.label).foregroundStyle(Dash.dim).padding(.horizontal, 10).padding(.bottom, 4)
            ForEach(store.visible.filter { MascotArt.providers.contains($0.id) }) { s in
                HStack(spacing: 10) {
                    WindowArc(progress: arcProgress(s), color: Theme.color(for: s.id), lineWidth: 1.6)
                        .frame(width: 22, height: 13)
                    Text(s.name).font(.system(size: 13)).foregroundStyle(s.id == "claude" ? .white : Color.white.opacity(0.75))
                    Spacer()
                    Text(sidebarValue(s)).font(Dash.num(12)).foregroundStyle(Theme.color(for: s.id))
                }
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(s.id == "claude" ? Color.white.opacity(0.06) : .clear))
            }
            Text("Automations").font(Dash.label).foregroundStyle(Dash.dim).padding(.horizontal, 10).padding(.top, 22).padding(.bottom, 4)
            sideToggle("Auto-start", on: store.prefs(for: "claude").autoStart,
                       help: "Start the next Claude window automatically when one runs out") { v in
                store.setPrefs("claude") { $0.autoStart = v }
            }
            sideToggle("Phone alerts", on: store.phoneEnabled,
                       help: store.ntfyTopic.isEmpty ? "Set a topic in Settings → Phone alerts first" : "Send reset alerts to your phone through ntfy") { v in
                if v && store.ntfyTopic.isEmpty {
                    // Phone alerts live on the General tab; open there rather than wherever Settings was left.
                    UserDefaults.standard.set("general", forKey: "settingsTab")
                    NSApp.activate(ignoringOtherApps: true); openWindow(id: "settings"); return
                }
                store.phoneEnabled = v
            }
            sideToggle("Mascots", on: store.mascots.enabled, help: "Show the desktop mascots") { v in
                store.mascots.enabled = v
            }
            sideToggle("Stay awake", on: store.keepAwake.mode != .off,
                       detail: store.keepAwake.mode == .off ? nil : (store.keepAwake.isHolding ? "holding" : "on battery"),
                       help: "Keep the Mac from idle-sleeping when plugged in, so auto-start and alerts run on time") { v in
                store.keepAwake.mode = v ? .pluggedIn : .off
            }
            Spacer()
            if let t = usage.lastScan {
                Text("Usage read \(Fmt.clock.string(from: t))").font(.system(size: 11)).foregroundStyle(Dash.faint).padding(.horizontal, 10)
            }
        }
        .padding(.vertical, 18).padding(.horizontal, 10)
        .frame(width: 220)
    }

    /// A real switch: clicking the row flips the setting, the same one Settings changes.
    private func sideToggle(_ name: String, on: Bool, detail: String? = nil, help: String, set: @escaping (Bool) -> Void) -> some View {
        Button { set(!on) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.85))
                    if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(Dash.faint) }
                }
                Spacer()
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? Dash.claude.opacity(0.85) : Color.white.opacity(0.14)).frame(width: 30, height: 17)
                    Circle().fill(.white).frame(width: 13, height: 13).padding(2)
                }
                .animation(.easeOut(duration: 0.15), value: on)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func arcProgress(_ s: WindowStatus) -> Double {
        if let u = s.usedPercent { return u / 100 }
        if case .active(let end) = s.state {
            let w: Double = s.id == "gemini" ? 86400 : 5 * 3600
            return 1 - min(1, end.timeIntervalSince(store.now) / w)
        }
        return 0
    }

    private func sidebarValue(_ s: WindowStatus) -> String {
        switch s.state {
        case .ready: return "ready"
        case .unavailable: return "--"
        case .active(let end):
            if let u = s.usedPercent { return "\(Int(u.rounded()))%" }
            return Fmt.short(end.timeIntervalSince(store.now))
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        GlowCard(glow: Color(hex: 0xFF8A2A), glowAt: UnitPoint(x: 0.5, y: 0.55), glowSize: 300, glowOpacity: 0.6) {
            let c = claude
            let end = c?.resetsAt
            let remaining = end.map { max(0, $0.timeIntervalSince(store.now)) } ?? 0
            let elapsed = end != nil ? 1 - remaining / (5 * 3600) : 0
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        CardHeader(title: "Claude session window", subtitle: heroSubtitle(c))
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
                        if store.liveNeedsSignIn {
                            HStack(spacing: 6) {
                                Text("Live usage paused: Claude Code is signed out.").foregroundStyle(Color(hex: 0xFFB13D))
                                Button(store.signingIn ? "Waiting for browser…" : "Sign in") { store.fixClaudeSignIn() }
                                    .buttonStyle(.plain).foregroundStyle(.white).underline()
                            }
                        } else if let out = store.forecast.runsOutAt, c?.state != .ready {
                            Text("at this pace you run out around \(Fmt.clock.string(from: out))").foregroundStyle(Color(hex: 0xFF8A5C))
                        } else {
                            Text(c?.state == .ready ? "send a message to start the clock" : "until a fresh window").foregroundStyle(Dash.dim)
                        }
                    }
                    .font(Dash.label)
                    }
                    .layoutPriority(1)
                    WindowArc(progress: elapsed, color: Dash.claude)
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
                        .overlay(alignment: .leading) {
                            // Where the budget's cap sits on the bar, so the line below has a place to point at.
                            if let b = store.budget {
                                GeometryReader { g in
                                    Capsule().fill(.white.opacity(0.85))
                                        .frame(width: 2, height: 18)
                                        .offset(x: g.size.width * CGFloat(b.maxPercent) / 100 - 1, y: -3)
                                }
                            }
                        }
                    if let b = store.budget { budgetLine(b, used: store.budgetUsed) }
                }
            }
            .frame(height: 312)
        }
    }

    /// Where the numbers come from, and why they're a guess when they are, e.g. "Estimated from your activity ·
    /// live usage off". An estimate shouldn't read as confidently as a live reading.
    private func heroSubtitle(_ c: WindowStatus?) -> String {
        guard let c else { return "" }
        let base = c.isEstimate ? "Estimated from your activity" : c.source
        guard let note = store.estimateNote(for: c) else { return base }
        // The note starts with "estimated" or "usage unknown"; only its reason adds anything to the base line.
        let why = note.components(separatedBy: " · ").last ?? note
        return c.isEstimate ? "\(base) · \(why)" : "\(base) · usage unknown, \(why)"
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
            Button { store.clearBudget() } label: {
                HStack(spacing: 3) { Image(systemName: "xmark"); Text("Clear") }
            }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
            .help("Remove this budget. Agents stop getting wrap-up and downshift advice for it.")
        }
        .font(Dash.label)
        .padding(.top, 8)
        .help(b.advice(used: used))
    }

    // MARK: Value

    private var valueCard: some View {
        GlowCard(glow: Dash.green, glowAt: UnitPoint(x: 1.0, y: 1.0), glowSize: 260, glowOpacity: 0.45) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Value \(rangePhrase)", subtitle: "API price of your tokens vs what you pay")
                Spacer(minLength: 0)
                if let m = usage.valueMultiple {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: m >= 100 ? "%.0f" : "%.1f", m)).font(Dash.hero(92)).foregroundStyle(.white)
                        Text("×").font(Dash.hero(34)).foregroundStyle(Dash.dim)
                        Spacer()
                        planButton("Edit plan")
                    }
                    (Text(Dash.money(usage.totalCost)).foregroundColor(.white) + Text(" of API value on ").foregroundColor(Dash.dim)
                        + Text(Dash.money(usage.planCostForRange)).foregroundColor(.white) + Text(" of plan").foregroundColor(Dash.dim))
                        .font(.system(size: 13))
                } else {
                    Text(Dash.money(usage.totalCost)).font(Dash.hero(72)).foregroundStyle(.white)
                    Text("of API value \(rangePhrase).").font(.system(size: 13)).foregroundStyle(Dash.dim)
                    planButton("Add your plan price to see the multiple").padding(.top, 10)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cache saved you").font(Dash.label).foregroundStyle(Dash.dim)
                        Text(Dash.money(usage.cacheSaved)).font(Dash.num(24, .light)).foregroundStyle(Dash.green)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Responses").font(Dash.label).foregroundStyle(Dash.dim)
                        Text(NumberFormatter.localizedString(from: NSNumber(value: usage.inRange.count), number: .decimal))
                            .font(Dash.num(24, .light)).foregroundStyle(.white)
                    }
                }
            }
            .frame(height: 312)
        }
    }

    private func planButton(_ title: String) -> some View {
        Button { editingPlan = true } label: {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.black)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.9)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $editingPlan, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("What you pay per month").font(.system(size: 13, weight: .medium))
                HStack {
                    Text("$")
                    TextField("150", value: $usage.planMonthlyUSD, format: .number).frame(width: 90)
                        .onSubmit { editingPlan = false }
                }
                Text("Add up all your Claude plans. Used only on this Mac to work out the multiple.")
                    .font(.caption).foregroundStyle(.secondary).frame(width: 220, alignment: .leading)
            }
            .padding(14)
        }
    }

    private var rangePhrase: String {
        switch usage.range {
        case .today: return "today"
        case .week: return "this week"
        case .month: return "this month"
        case .all: return "in \(Int(UsageStore.historyDays)) days"
        }
    }

    // MARK: Windows

    private var windowsCard: some View {
        GlowCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    CardHeader(title: "Your windows", subtitle: "Every 5-hour Claude window, last 7 days")
                    Spacer()
                    HStack(spacing: 16) {
                        LegendDot(color: Dash.claude, text: "you started it")
                        LegendDot(color: Dash.claude, text: "auto-start", outlined: true)
                        LegendDot(color: Color(hex: 0xFF5C3A), text: "hit the limit")
                    }
                }
                WindowBarcode(windows: usage.windows(days: 7)).frame(height: 230)
            }
        }
    }

    // MARK: Mix and heatmap

    private var mixCard: some View {
        let mix = usage.tokenMix
        let pct: (Int) -> String = { n in
            let p = mix.total > 0 ? Double(n) / Double(mix.total) * 100 : 0
            return p >= 10 ? String(format: "%.0f%%", p) : String(format: "%.1f%%", p)
        }
        return GlowCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    CardHeader(title: "Token mix", subtitle: "Each square is 1% of tokens \(rangePhrase)")
                    Spacer()
                    Text(Dash.tokens(mix.total)).font(Dash.num(28, .light)).foregroundStyle(.white)
                }
                HStack(alignment: .center, spacing: 22) {
                    TokenGrid(mix: mix).frame(width: 300)
                    VStack(spacing: 0) {
                        legendRow(Dash.blue, "Cache read", pct(mix.cacheRead), first: true)
                        legendRow(Dash.violet, "Cache write", pct(mix.cacheWrite))
                        legendRow(Dash.claude, "Output", pct(mix.output))
                        legendRow(.white.opacity(0.85), "Input", pct(mix.input))
                    }
                }
            }
        }
    }

    private func legendRow(_ c: Color, _ name: String, _ v: String, first: Bool = false) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 9, height: 9)
            Text(name).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.85))
            Spacer()
            Text(v).font(Dash.num(13))
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Dash.line).frame(height: 1) } }
    }

    private var heatCard: some View {
        GlowCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    CardHeader(title: "When you build", subtitle: "Output by weekday and hour, last 5 weeks")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(usage.busiestHour.map(hourLabel) ?? "--").font(Dash.num(28, .light)).foregroundStyle(.white)
                        Text("busiest hour").font(Dash.label).foregroundStyle(Dash.dim)
                    }
                }
                Heatmap(grid: usage.heatmap).frame(height: 104)
            }
        }
    }

    private func hourLabel(_ h: Int) -> String {
        h == 0 ? "12 AM" : h < 12 ? "\(h) AM" : h == 12 ? "12 PM" : "\(h - 12) PM"
    }

    // MARK: Sessions

    private var sessionsCard: some View {
        let list = Array(usage.sessions.prefix(8))
        return GlowCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Sessions").font(Dash.title)
                    Spacer()
                    Text("by cost").font(Dash.label).foregroundStyle(Dash.dim)
                }
                .padding(.bottom, 4)
                if list.isEmpty {
                    Text(usage.loading ? "Reading your sessions…" : "No sessions in this range").font(.system(size: 13)).foregroundStyle(Dash.dim)
                }
                ForEach(list) { s in
                    let selected = (usage.selectedSession ?? list.first?.id) == s.id
                    Button { usage.selectedSession = s.id } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(.system(size: 13)).foregroundStyle(selected ? .white : Color.white.opacity(0.8)).lineLimit(1)
                                Text("\(Fmt.when(s.end, now: store.now)) · \(s.projectName)").font(.system(size: 11)).foregroundStyle(Dash.faint).lineLimit(1)
                            }
                            Spacer()
                            Text(Dash.money(s.cost)).font(Dash.num(14)).foregroundStyle(selected ? Dash.claude : .white)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.white.opacity(0.06) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sessionDetailCard: some View {
        let list = usage.sessions
        let s = list.first { $0.id == (usage.selectedSession ?? list.first?.id) }
        return GlowCard(glow: Dash.claude, glowAt: UnitPoint(x: 1, y: 0), glowSize: 220, glowOpacity: 0.3) {
            if let s {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).font(Dash.title).lineLimit(1)
                            Text([prettyModel(s.topModel), s.apiMillis.map { "\(Dash.duration($0)) of API time" }].compactMap { $0 }.joined(separator: " · "))
                                .font(Dash.label).foregroundStyle(Dash.dim)
                        }
                        Spacer()
                        Text(Dash.money(s.cost)).font(Dash.num(32, .light))
                    }
                    shareBar(s)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], spacing: 0) {
                        StatRow(label: "Output", value: Dash.tokens(s.output))
                        StatRow(label: "Cache read", value: Dash.tokens(s.cacheRead))
                        StatRow(label: "Cache write", value: Dash.tokens(s.cacheWrite))
                        StatRow(label: "Cache hit", value: String(format: "%.0f%%", s.cacheHit * 100))
                        StatRow(label: "Tool calls", value: "\(s.tools)")
                        StatRow(label: "MCP calls", value: "\(s.mcpCalls)")
                        StatRow(label: "Web searches", value: "\(s.webSearches)")
                        StatRow(label: "Subagent calls", value: "\(s.subagentCalls)")
                    }
                }
            } else {
                Text("Pick a session").foregroundStyle(Dash.dim)
            }
        }
    }

    // MARK: Projects

    @State private var renaming: String?
    @State private var draftName = ""

    private var projectsCard: some View {
        let list = Array(usage.projects.prefix(12))
        let maxCost = max(0.01, list.first?.cost ?? 1)
        return GlowCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    CardHeader(title: "Projects", subtitle: "Click a name to rename it. Subfolders and worktrees count as one project.")
                    Spacer()
                    Text("\(usage.projects.count) projects \(rangePhrase)").font(Dash.label).foregroundStyle(Dash.dim)
                }
                .padding(.bottom, 8)
                ForEach(list) { p in
                    HStack(spacing: 14) {
                        Group {
                            if renaming == p.root {
                                TextField("Name", text: $draftName)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                                    .onSubmit { ProjectNames.shared.rename(p.root, to: draftName); renaming = nil }
                                    .onExitCommand { renaming = nil }
                            } else {
                                Button {
                                    draftName = ProjectNames.shared.name(for: p.root); renaming = p.root
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ProjectNames.shared.name(for: p.root)).font(.system(size: 13)).foregroundStyle(.white).lineLimit(1)
                                        Text(p.root.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 10)).foregroundStyle(Dash.faint).lineLimit(1).truncationMode(.middle)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Rename")
                            }
                        }
                        .frame(width: 300, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.05))
                                Capsule().fill(Dash.claude.opacity(0.8)).frame(width: max(4, g.size.width * p.cost / maxCost))
                            }
                        }
                        .frame(height: 6)
                        Text("\(p.sessions) session\(p.sessions == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(Dash.dim).frame(width: 70, alignment: .trailing)
                        Text(Dash.money(p.cost)).font(Dash.num(13)).frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .top) { Rectangle().fill(Dash.line).frame(height: 1) }
                }
            }
        }
    }

    private func shareBar(_ s: SessionSummary) -> some View {
        let total = max(0.0001, s.cost)
        var parts: [(String, Double, Color)] = [("Main", s.mainCost, Dash.claude), ("Subagents", s.subagentCost, Color(hex: 0xFFC98F))]
        let palette = [Dash.blue, Dash.violet, Dash.green, Color(hex: 0xFF5C7A)]
        for (i, (k, v)) in s.mcpCost.sorted(by: { $0.value > $1.value }).prefix(4).enumerated() { parts.append((k, v, palette[i % palette.count])) }
        parts = parts.filter { $0.1 > 0 }
        return VStack(alignment: .leading, spacing: 8) {
            Text("What used the window").font(Dash.label).foregroundStyle(Dash.dim)
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(parts.indices, id: \.self) { i in
                        Rectangle().fill(parts[i].2).frame(width: max(2, (g.size.width - CGFloat(parts.count - 1) * 2) * parts[i].1 / total))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            HStack(spacing: 14) {
                ForEach(parts.indices, id: \.self) { i in
                    Text("\(parts[i].0) \(Int((parts[i].1 / total * 100).rounded()))%")
                        .font(.system(size: 11)).foregroundStyle(i == 0 ? Color.white.opacity(0.85) : Dash.dim).lineLimit(1)
                }
            }
        }
    }

    private func prettyModel(_ id: String) -> String? {
        guard !id.isEmpty else { return nil }
        let parts = id.replacingOccurrences(of: "claude-", with: "").split(separator: "-")
        guard let fam = parts.first else { return id }
        let ver = parts.dropFirst().prefix(2).filter { $0.count <= 2 }.joined(separator: ".")
        return fam.prefix(1).uppercased() + fam.dropFirst() + (ver.isEmpty ? "" : " \(ver)")
    }
}
