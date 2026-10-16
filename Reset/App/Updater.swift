import Foundation
import Observation

/// Asks GitHub once a day whether a newer Reset release exists. No dependencies, no installer: it shows the new
/// version and what's in it, and downloads the DMG (or, for a copy built from source, says how to rebuild).
@Observable
final class Updater {
    struct Release {
        var version: String
        var url: URL
        var notes: String
        /// The release's .dmg, so Download saves it instead of opening a page to find it on.
        var download: URL? = nil
        var whatsNew: String { Updater.whatsNew(notes) }
    }

    var automatic: Bool { didSet { UserDefaults.standard.set(automatic, forKey: "checkUpdates") } }
    private(set) var available: Release?
    private(set) var lastChecked: Date?
    private(set) var checking = false
    private(set) var lastError: String?

    private var timer: Timer?
    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    init() {
        automatic = UserDefaults.standard.object(forKey: "checkUpdates") as? Bool ?? true
    }

    func start() {
        guard !Demo.isOn else { return }
        if automatic { check() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            if self?.automatic == true { self?.check() }
        }
    }

    func check() {
        guard !checking, let api = URL(string: ResetInfo.repoURL.replacingOccurrences(of: "https://github.com/", with: "https://api.github.com/repos/") + "/releases/latest")
        else { return }
        checking = true
        var req = URLRequest(url: api, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Reset/\(Self.current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let obj = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                self.lastChecked = Date()
                guard err == nil, code == 200, let obj, let tag = obj["tag_name"] as? String,
                      let page = (obj["html_url"] as? String).flatMap(URL.init(string:)) else {
                    self.lastError = code == 404 ? "No releases yet"
                        : code == 403 || code == 429 ? "GitHub is limiting checks; try again in an hour" : "Couldn't reach GitHub"
                    return
                }
                self.lastError = nil
                let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let dmg = (obj["assets"] as? [[String: Any]] ?? [])
                    .first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
                    .flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
                self.available = Self.isNewer(version, than: Self.current) && version != self.skipped
                    ? Release(version: version, url: page, notes: obj["body"] as? String ?? "", download: dmg) : nil
            }
        }.resume()
    }

    /// A version the user chose to skip: not offered again, though a later one is.
    private(set) var skipped = UserDefaults.standard.string(forKey: "skippedVersion")

    func skip(_ r: Release) {
        skipped = r.version
        UserDefaults.standard.set(r.version, forKey: "skippedVersion")
        available = nil
    }

    /// A copy built from source with a team ID has widgets; the download is ad-hoc signed and has none, so
    /// updating from it would quietly remove them. Such a copy is told how to rebuild instead.
    static var builtFromSource: Bool { ProblemReport.hasTeamSignature }
    static let rebuildCommand = "git pull && TEAM=<your team ID> ./scripts/build.sh --install"

    /// The "New in…" part of the release notes, without the install steps every release repeats.
    static func whatsNew(_ notes: String) -> String {
        var text = notes
        if let r = text.range(of: "**New in") { text = String(text[r.lowerBound...]) }
        if let r = text.range(of: "Full history") { text = String(text[..<r.lowerBound]) }
        text = text.replacingOccurrences(of: "**", with: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Numeric comparison of dotted versions: 0.10 is newer than 0.9.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
