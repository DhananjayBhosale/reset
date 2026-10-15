import Foundation

/// The Claude Code command-line tool: whether it is signed in, and signing it in. Live usage and auto-start
/// both depend on it, and the desktop app has its own separate login, so it can be signed out without anyone noticing.
enum ClaudeCLI {
    static var path: String? {
        let home = NSHomeDirectory()
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    struct Status { var installed: Bool; var signedIn: Bool; var plan: String? }

    /// `claude auth status` prints JSON with `loggedIn` and `subscriptionType`. Only those two fields are read.
    static func status(completion: @escaping (Status) -> Void) {
        guard let path else { completion(Status(installed: false, signedIn: false, plan: nil)); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = ["auth", "status"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            var result = Status(installed: true, signedIn: false, plan: nil)
            if (try? p.run()) != nil {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    result.signedIn = (obj["loggedIn"] as? Bool) ?? false
                    result.plan = obj["subscriptionType"] as? String
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Runs `claude auth login`, which opens the browser and finishes once the user approves there.
    static func signIn(completion: @escaping (Bool) -> Void) {
        guard let path else { completion(false); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = ["auth", "login"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 300, execute: timeout)
            var ok = false
            if (try? p.run()) != nil {
                p.waitUntilExit()
                ok = p.terminationStatus == 0
            }
            timeout.cancel()
            DispatchQueue.main.async { completion(ok) }
        }
    }
}

/// Which AI tools this Mac has, from their usual folders and apps.
enum InstalledTools {
    static func detect() -> Set<String> {
        let home = NSHomeDirectory(), fm = FileManager.default
        var out: Set<String> = []
        if fm.fileExists(atPath: "\(home)/.claude") || ClaudeCLI.path != nil { out.insert("claude") }
        if fm.fileExists(atPath: "\(home)/.codex/sessions") { out.insert("codex") }
        if fm.fileExists(atPath: "\(home)/.gemini") { out.insert("gemini") }
        if fm.fileExists(atPath: "/Applications/Antigravity.app") { out.insert("antigravity") }
        return out
    }
}
