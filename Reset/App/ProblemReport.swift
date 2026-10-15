import Foundation
import Security

/// "Report a problem": a GitHub issue pre-filled with what's needed to help, opened in the browser so the
/// person sees every word before deciding to submit. Only versions and on/off states go in, never usage
/// numbers, project or folder names, the ntfy topic, account details or anything else personal.
enum ProblemReport {
    struct Facts {
        var resetVersion: String
        var macOS: String
        var macModel: String
        var toolsOn: [String]
        var liveUsage: String          // "off", "working", "problem: …" (Reset's own wording, no numbers)
        var claudeAccuracy: String     // "solid" or the estimate note
        var logFormat: String          // the format check's verdict
        var lastAutoStart: String      // "never", or the outcome kind
        var stayAwake: String
        var phoneAlerts: Bool
        var widgetsSigned: Bool
    }

    static func body(_ f: Facts) -> String {
        """
        **What happened?**
        <!-- What you expected, what you saw instead, and roughly when. A screenshot helps. -->


        **Steps to reproduce (if you know them)**


        ---
        <details><summary>Diagnostics (no usage numbers or personal details)</summary>

        - Reset \(f.resetVersion), macOS \(f.macOS), \(f.macModel)
        - Tools on: \(f.toolsOn.isEmpty ? "none" : f.toolsOn.joined(separator: ", "))
        - Live usage: \(f.liveUsage)
        - Claude numbers: \(f.claudeAccuracy)
        - Log format check: \(f.logFormat)
        - Last auto-start: \(f.lastAutoStart)
        - Stay awake: \(f.stayAwake)
        - Phone alerts: \(f.phoneAlerts ? "on" : "off")
        - Widgets available (signed build): \(f.widgetsSigned ? "yes" : "no")

        </details>
        """
    }

    /// The new-issue link. GitHub accepts title and body as query parameters; the body is far below the
    /// length at which browsers or GitHub would cut it off.
    static func url(repo: String, facts: Facts) -> URL? {
        var c = URLComponents(string: repo + "/issues/new")
        c?.queryItems = [URLQueryItem(name: "title", value: "Problem: "), URLQueryItem(name: "body", value: body(facts))]
        return c?.url
    }

    /// Whether this copy has a real (team) signature, which macOS needs before it will list the widgets.
    static var hasTeamSignature: Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }
        return (dict[kSecCodeInfoTeamIdentifier as String] as? String).map { !$0.isEmpty } ?? false
    }

    /// "Mac15,6"-style model identifier: the hardware family, not anything that identifies the person.
    static var macModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }
}
