import Foundation

/// Wiring Reset into Claude Code: the status line (`statusLine` in ~/.claude/settings.json) and the MCP server
/// (`mcpServers.reset` in ~/.claude.json). Settings used to offer only snippets to paste into those files by hand,
/// with the MCP path fixed to /Applications, and no way to tell whether either was already set up.
enum ClaudeIntegration {
    enum State: Equatable {
        case missing
        case installed
        /// Set up, but pointing somewhere else: another status line, or reset-mcp at an old path (the app moved).
        case other(String)
        /// Reset's older status line, which can't tell when Reset isn't running.
        case outdated
    }

    static var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }
    static var settingsURL: URL { home.appendingPathComponent(".claude/settings.json") }
    static var claudeJSONURL: URL { home.appendingPathComponent(".claude.json") }

    /// Where this copy of Reset keeps its MCP server, wherever the app lives.
    static var mcpPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/reset-mcp").path }

    /// Shows Reset's line while its heartbeat is fresh (touched in the last 3 minutes), else says Reset isn't
    /// running: a plain `cat` kept showing the countdown from whenever Reset quit.
    static let statusLineCommand = #"d="$HOME/Library/Application Support/Reset"; if [ -n "$(find "$d/running" -mmin -3 2>/dev/null)" ]; then cat "$d/statusline.txt"; else echo "◷ Reset isn't running"; fi"#

    private static func json(_ url: URL) -> [String: Any]? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    static func statusLineState(settings: URL = settingsURL) -> State {
        guard let line = json(settings)?["statusLine"] as? [String: Any] else { return .missing }
        let command = line["command"] as? String ?? ""
        guard command.contains("statusline.txt"), command.contains("Reset") else { return .other(command) }
        return command.contains("/running") ? .installed : .outdated
    }

    static func mcpState(claudeJSON: URL = claudeJSONURL, path: String = mcpPath) -> State {
        guard let server = (json(claudeJSON)?["mcpServers"] as? [String: Any])?["reset"] as? [String: Any] else { return .missing }
        let command = server["command"] as? String ?? ""
        return command == path ? .installed : .other(command)
    }

    enum InstallError: LocalizedError {
        case unreadable
        var errorDescription: String? { "~/.claude/settings.json isn't valid JSON, so Reset left it alone." }
    }

    /// Adds (or replaces) `statusLine`, keeping every other setting. The file as it was is saved next to it as
    /// settings.json.before-reset first, because rewriting it changes its formatting and key order.
    static func installStatusLine(settings: URL = settingsURL) throws {
        let fm = FileManager.default
        var obj: [String: Any] = [:]
        if let d = try? Data(contentsOf: settings) {
            guard let parsed = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw InstallError.unreadable }
            obj = parsed
            let backup = settings.appendingPathExtension("before-reset")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: settings, to: backup)
        }
        obj["statusLine"] = ["type": "command", "command": statusLineCommand]
        try fm.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: settings, options: .atomic)
    }

    /// The `claude mcp` calls that register this copy's server, replacing one at an old path.
    static func mcpCommands(state: State, path: String = mcpPath) -> [[String]] {
        let add = ["mcp", "add", "--scope", "user", "reset", "--", path]
        if case .other = state { return [["mcp", "remove", "--scope", "user", "reset"], add] }
        return [add]
    }

    /// Runs those through Claude Code's own CLI, which owns ~/.claude.json. Calls back on the main queue with
    /// nil on success, or what went wrong.
    static func installMCP(completion: @escaping (String?) -> Void) {
        guard let cli = ClaudeCLI.path else { completion("Claude Code's command-line tool wasn't found."); return }
        let steps = mcpCommands(state: mcpState())
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            for args in steps {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: cli)
                p.arguments = args
                let err = Pipe()
                p.standardOutput = FileHandle.nullDevice
                p.standardError = err
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch { failure = error.localizedDescription; break }
                let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                p.waitUntilExit()
                // A failed remove (nothing there after all) doesn't matter; a failed add does.
                if p.terminationStatus != 0, args[1] == "add" {
                    failure = msg.split(separator: "\n").first.map(String.init) ?? "claude mcp add exited \(p.terminationStatus)"
                    break
                }
            }
            DispatchQueue.main.async { completion(failure) }
        }
    }
}
