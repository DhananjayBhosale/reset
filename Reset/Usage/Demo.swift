import Foundation

/// Made-up usage for screenshots and screen recordings: `open -a Reset --args -demo YES`.
/// Nothing is read from disk and no alerts or auto-starts fire while it is on.
enum Demo {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "demo") }

    static let projects: [(String, String, Double)] = [
        ("/Users/demo/Developer/landing-page", "Landing page redesign", 1.0),
        ("/Users/demo/Developer/ios-onboarding", "iOS onboarding flow", 0.8),
        ("/Users/demo/Developer/api-server", "API rate limiter", 0.65),
        ("/Users/demo/Videos/launch-video", "Launch video edit", 0.5),
        ("/Users/demo/Developer/design-system", "Design system tokens", 0.4),
        ("/Users/demo/Writing/newsletter", "Weekly newsletter", 0.25),
        ("/Users/demo/Developer/cli-tool", "CLI release script", 0.2),
    ]

    static func calls(now: Date = Date()) -> (calls: [Call], titles: [String: String], limitHits: [Date], api: [String: Int]) {
        var rng = SeededRandom(seed: 42)
        var calls: [Call] = [], titles: [String: String] = [:], hits: [Date] = [], api: [String: Int] = [:]
        let cal = Calendar.current
        for dayBack in stride(from: 29, through: 0, by: -1) {
            let day = cal.startOfDay(for: now.addingTimeInterval(-Double(dayBack) * 86400))
            if rng.next() < 0.18 && dayBack > 0 { continue }   // a few days off
            let sessions = 1 + Int(rng.next() * 3)
            for s in 0..<sessions {
                let p = projects[Int(rng.next() * Double(projects.count)) % projects.count]
                let id = "demo-\(dayBack)-\(s)"
                titles[id] = p.1
                let startHour = [10.0, 13.5, 16.0, 21.5, 23.0][Int(rng.next() * 5) % 5] + rng.next()
                var t = day.addingTimeInterval(startHour * 3600)
                let n = 120 + Int(rng.next() * 900 * p.2)
                for k in 0..<n {
                    t = t.addingTimeInterval(20 + rng.next() * 70)
                    if t > now { break }
                    let model = rng.next() < 0.85 ? "claude-opus-5-5" : "claude-sonnet-5-5"
                    let cr = Int(60_000 + rng.next() * 220_000), out = Int(200 + rng.next() * 2400)
                    let cw = k % 12 == 0 ? Int(8_000 + rng.next() * 40_000) : 0
                    let cost = Pricing.claude(model).map { Pricing.cost($0, input: 3, cw5: 0, cw1h: cw, cacheRead: cr, output: out) } ?? 0
                    let mcp: [String: Int] = rng.next() < 0.08 ? [["github", "figma", "linear"][Int(rng.next() * 3) % 3]: 1] : [:]
                    calls.append(Call(id: "\(id)-\(k)", time: t, model: model, session: id, project: p.0, sidechain: rng.next() < 0.22,
                                      input: 3, cw5: 0, cw1h: cw, cacheRead: cr, output: out, advisorTokens: 0,
                                      tools: rng.next() < 0.6 ? 1 : 0, mcpServers: mcp, webSearches: rng.next() < 0.02 ? 1 : 0,
                                      mcpAttribution: mcp.keys.first, cost: cost, autoStart: k == 0 && rng.next() < 0.15))
                }
                api[id] = Int(Double(n) * 9_000)
            }
            if rng.next() < 0.25 && dayBack > 0 { hits.append(day.addingTimeInterval(17 * 3600)) }
        }
        return (calls.sorted { $0.time < $1.time }, titles, hits, api)
    }

    static func claude(now: Date = Date()) -> WindowStatus {
        WindowStatus(id: "claude", name: "Claude", state: .active(resetsAt: now.addingTimeInterval(2 * 3600 + 41 * 60)),
                     usedPercent: 38, isEstimate: false, source: "Live from your Claude account", secondary: nil, canAutoStart: true)
    }
}

/// Small deterministic generator so demo data is the same every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}
