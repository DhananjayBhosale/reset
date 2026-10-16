import SwiftUI

/// What's in a new release, and how to get it: the DMG for downloaded copies, a rebuild for copies built from
/// source (whose widgets the ad-hoc-signed download doesn't have).
struct UpdateNotes: View {
    let release: Updater.Release

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's new in \(release.version)").font(.system(size: 13, weight: .semibold))
            ScrollView {
                Text((try? AttributedString(markdown: release.whatsNew,
                                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(release.whatsNew))
                    .font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(maxHeight: 240)
            if Updater.builtFromSource {
                Text("You built this copy yourself, which is how it has widgets. The download doesn't have them, so update by rebuilding:")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(Updater.rebuildCommand).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button(Updater.builtFromSource ? "Copy command and open release" : "Download") { Self.act(on: release) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    /// Download the DMG, or for a copy built from source, copy the rebuild command and open the release page.
    static func act(on r: Updater.Release) {
        if Updater.builtFromSource {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Updater.rebuildCommand, forType: .string)
            NSWorkspace.shared.open(r.url)
        } else {
            NSWorkspace.shared.open(r.download ?? r.url)
        }
    }
}
