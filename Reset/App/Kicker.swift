import Foundation

/// Auto-start: when a provider's window has run out, send it a one-word prompt so the next window
/// starts right away instead of waiting for you to wake up. Off by default for every provider.
final class Kicker {
    private var running: Set<String> = []
    private var nextAllowed: [String: Date] = [:]
    private var failures: [String: Int] = [:]

    static func defaultCommands() -> [String: String] {
        let home = NSHomeDirectory()
        func firstExisting(_ paths: [String]) -> String? {
            paths.first { FileManager.default.isExecutableFile(atPath: $0) }
        }
        let claude = firstExisting(["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"])
            .map { "\"\($0)\"" } ?? "claude"
        let codex = firstExisting(["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex",
                                   "/Applications/Codex.app/Contents/Resources/codex"])
            .map { "\"\($0)\"" } ?? "codex"
        return [
            // No tools and no MCP servers: the kick only needs one API call to open the window. It must
            // still write a transcript (no --no-session-persistence), because that is how Reset sees it.
            "claude": "\(claude) -p \"hi\" --model haiku --tools \"\" --strict-mcp-config",
            "codex": "\(codex) exec --skip-git-repo-check \"hi\"",
        ]
    }

    /// Runs `command` in a login shell. Rate-limited per provider: 10 min after a success, and
    /// 15, 30, 60 min after consecutive failures, so a wrong estimate never turns into a retry storm.
    func kick(_ id: String, name: String, command: String, force: Bool = false,
              log: @escaping (String) -> Void, done: @escaping (Bool) -> Void) {
        let now = Date()
        guard !running.contains(id) else { return }
        if !force, let t = nextAllowed[id], now < t { return }
        running.insert(id)
        log("Auto-starting \(name)")

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Reset/kick", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        p.currentDirectoryURL = dir
        p.standardInput = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out

        // Drain output while the process runs, so a chatty command can never fill the pipe and hang.
        var collected = Data()
        let reader = DispatchGroup()
        reader.enter()
        DispatchQueue.global(qos: .utility).async {
            collected = out.fileHandleForReading.readDataToEndOfFile()
            reader.leave()
        }
        let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
        p.terminationHandler = { [weak self] proc in
            timeout.cancel()
            _ = reader.wait(timeout: .now() + 5)
            let text = String(data: collected, encoding: .utf8) ?? ""
            let tail = text.split(separator: "\n").last.map(String.init) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                self.running.remove(id)
                if proc.terminationStatus == 0 {
                    self.failures[id] = 0
                    self.nextAllowed[id] = Date().addingTimeInterval(600)
                    log("\(name) started a new window")
                    done(true)
                } else {
                    let n = (self.failures[id] ?? 0) + 1
                    self.failures[id] = n
                    let wait = Double(15 * (1 << min(n - 1, 2))) * 60
                    self.nextAllowed[id] = Date().addingTimeInterval(wait)
                    log("\(name) auto-start failed (exit \(proc.terminationStatus)): \(tail.prefix(120))")
                    done(false)
                }
            }
        }
        do {
            try p.run()
            DispatchQueue.global().asyncAfter(deadline: .now() + 180, execute: timeout)
        } catch {
            running.remove(id)
            log("\(name) auto-start could not run: \(error.localizedDescription)")
            done(false)
        }
    }
}
