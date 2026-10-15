import Foundation
import Observation

/// Groups sessions by project root and gives each project a readable name, which the user can override.
@Observable
final class ProjectNames {
    static let shared = ProjectNames()

    private(set) var overrides: [String: String] {
        didSet { UserDefaults.standard.set(overrides, forKey: "projectNames") }
    }

    init() {
        overrides = UserDefaults.standard.dictionary(forKey: "projectNames") as? [String: String] ?? [:]
    }

    private static let home = NSHomeDirectory()
    /// Folders that hold projects rather than being one.
    private static let containers = ["Desktop", "Developer", "Documents", "Downloads", "Projects", "Code", "src", "repos", "workspace", "dev", "Sites"]

    /// The project a working directory belongs to: the first folder below a container like ~/Desktop,
    /// with git worktrees and any deeper subfolders folded into it.
    static func root(of path: String) -> String {
        var p = path
        if let r = p.range(of: "/.claude/worktrees/") { p = String(p[..<r.lowerBound]) }
        guard p.hasPrefix(home) else { return p }
        let rel = p.dropFirst(home.count).split(separator: "/").map(String.init)
        guard let first = rel.first else { return home }
        var depth = 1
        if containers.contains(first) {
            depth = 2
            // ~/Documents/<tool>/<project>, e.g. an IDE's workspace folder.
            if first == "Documents", rel.count >= 3, ["antigravity", "Cursor", "GitHub", "Projects", "Xcode"].contains(rel[1]) { depth = 3 }
        }
        return ([home] + rel.prefix(depth)).joined(separator: "/")
    }

    func name(for path: String) -> String {
        let r = Self.root(of: path)
        if let o = overrides[r], !o.isEmpty { return o }
        return Self.cleaned(r)
    }

    func rename(_ root: String, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || n == Self.cleaned(root) { overrides[root] = nil } else { overrides[root] = n }
    }

    /// A tidier version of the folder name: no list numbering, no dot-folders, separators turned into spaces.
    static func cleaned(_ root: String) -> String {
        if root == home { return "Home folder" }
        var n = (root as NSString).lastPathComponent
        if n.hasPrefix(".") { n.removeFirst() }
        n = n.replacingOccurrences(of: #"^\d+[\.\)]\s*"#, with: "", options: .regularExpression)
        n = n.replacingOccurrences(of: #"[-_]+"#, with: " ", options: .regularExpression)
        n = n.replacingOccurrences(of: #"\s+[A-F0-9]{8}(-[A-F0-9]{4}){3}-[A-F0-9]{12}$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return n.isEmpty ? "Untitled" : n
    }
}
