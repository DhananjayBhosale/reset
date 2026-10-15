import Foundation

/// Public API list prices, USD per million tokens, used to put a dollar value on subscription usage.
/// Checked against platform.claude.com/docs/en/about-claude/pricing and LiteLLM on 2026-10-14.
struct Price {
    var input: Double
    var cacheWrite5m: Double
    var cacheWrite1h: Double
    var cacheRead: Double
    var output: Double
    /// Haiku 5.5 bills the whole request at `above` once the prompt passes this many tokens.
    var tierAbove: Int? = nil
    var above: (input: Double, cw5: Double, cw1h: Double, cr: Double, out: Double)? = nil
}

enum Pricing {
    static func claude(_ model: String) -> Price? {
        let m = model.lowercased().replacingOccurrences(of: "[1m]", with: "")
        if m.contains("fable-5-1") || m.contains("mythos") { return Price(input: 10, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 0.25, output: 50) }
        if m.contains("fable") { return Price(input: 10, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 1, output: 50) }
        if m.contains("opus-5-5") { return Price(input: 4, cacheWrite5m: 5, cacheWrite1h: 8, cacheRead: 0.2, output: 20) }
        if m.contains("opus-4-1") || m.contains("opus-4-0") || m == "claude-opus-4" || m.contains("opus-4-2025") {
            return Price(input: 15, cacheWrite5m: 18.75, cacheWrite1h: 30, cacheRead: 1.5, output: 75)
        }
        if m.contains("opus") { return Price(input: 5, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.5, output: 25) }
        if m.contains("sonnet-5-5") { return Price(input: 2, cacheWrite5m: 2.5, cacheWrite1h: 4, cacheRead: 0.1, output: 10) }
        if m.contains("sonnet-5") { return Price(input: 2, cacheWrite5m: 2.5, cacheWrite1h: 4, cacheRead: 0.2, output: 10) }
        if m.contains("sonnet") { return Price(input: 3, cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.3, output: 15) }
        if m.contains("haiku-5-5") {
            return Price(input: 0.1, cacheWrite5m: 0.125, cacheWrite1h: 0.2, cacheRead: 0.01, output: 0.5,
                         tierAbove: 100_000, above: (0.5, 0.625, 1, 0.05, 2.5))
        }
        if m.contains("haiku") { return Price(input: 1, cacheWrite5m: 1.25, cacheWrite1h: 2, cacheRead: 0.1, output: 5) }
        return nil
    }

    static func cost(_ p: Price, input: Int, cw5: Int, cw1h: Int, cacheRead: Int, output: Int) -> Double {
        var r = (p.input, p.cacheWrite5m, p.cacheWrite1h, p.cacheRead, p.output)
        if let t = p.tierAbove, let a = p.above, input + cw5 + cw1h + cacheRead > t { r = a }
        return (Double(input) * r.0 + Double(cw5) * r.1 + Double(cw1h) * r.2 + Double(cacheRead) * r.3 + Double(output) * r.4) / 1_000_000
    }
}
