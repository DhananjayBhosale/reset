import AppIntents
import SwiftUI
import WidgetKit

/// The widgets' "Start now" button: asks the Reset app to start the next Claude window.
struct StartWindowIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Claude window"
    static var description = IntentDescription("Asks Reset to start your next Claude window now, the same way auto-start does.")

    func perform() async throws -> some IntentResult {
        StartRequest.post("claude")
        return .result()
    }
}

/// The button itself, or "Starting…" while the app is on it. Shown only when a fresh window is waiting.
struct StartNowButton: View {
    let snap: WidgetSnapshot?
    let date: Date
    var compact = false

    var body: some View {
        if W.isStarting(snap, at: date) {
            HStack(spacing: 5) {
                // Widgets can't animate a spinner (it draws as a placeholder), so a still hourglass it is.
                Image(systemName: "hourglass").font(.system(size: compact ? 10 : 11, weight: .semibold))
                Text("Starting…").font(.system(size: compact ? 11 : 12, weight: .medium))
            }
            .foregroundStyle(W.dim)
        } else {
            Button(intent: StartWindowIntent()) {
                Label("Start now", systemImage: "play.fill")
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, compact ? 10 : 12).padding(.vertical, compact ? 5 : 6)
                    .background(Capsule().fill(W.color("claude")))
            }
            .buttonStyle(.plain)
        }
    }
}
