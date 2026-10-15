import Foundation
import Observation

/// Asks GitHub once a day whether a newer Reset release exists. No dependencies, no installer:
/// it shows the new version and opens the release page.
@Observable
final class Updater {
    struct Release { var version: String; var url: URL; var notes: String }

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
                    self.lastError = code == 404 ? "No releases yet" : "Couldn't reach GitHub"
                    return
                }
                self.lastError = nil
                let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                self.available = Self.isNewer(version, than: Self.current)
                    ? Release(version: version, url: page, notes: obj["body"] as? String ?? "") : nil
            }
        }.resume()
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
