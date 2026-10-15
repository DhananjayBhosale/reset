import SwiftUI
import UserNotifications

@main
struct ResetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("Reset", id: "dashboard") {
            DashboardView(store: store, usage: store.usage)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 900)

        Window("Welcome to Reset", id: "welcome") {
            WelcomeWindow(store: store)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window("Reset Settings", id: "settings") {
            SettingsView(store: store)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuBarLabel: View {
    let store: Store
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        label
            .task {
                // `open -a Reset --args -openDashboard YES`, and the first launch after install, show the dashboard.
                // `-openSettings YES` opens Settings, for checking it (with `-simulateLogFormat`, the format warning);
                // `-renderSettings /path.png` also saves a picture of it, taken by Reset itself.
                let d = UserDefaults.standard
                if Demo.isOn { return }
                if !d.bool(forKey: "onboarded") || d.bool(forKey: "openWelcome") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "welcome")
                } else if d.bool(forKey: "openSettings") || d.string(forKey: "renderSettings") != nil {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                    if let path = d.string(forKey: "renderSettings") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            // A window's own view can be drawn into an image without Screen Recording permission.
                            guard let v = NSApp.windows.first(where: { $0.title == "Reset Settings" })?.contentView,
                                  let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
                            v.cacheDisplay(in: v.bounds, to: rep)
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                        }
                    }
                } else if d.bool(forKey: "openDashboard") || !d.bool(forKey: "dashboardSeen") {
                    d.set(true, forKey: "dashboardSeen")
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "dashboard")
                }
            }
    }

    @ViewBuilder private var label: some View {
        if let r = store.readyForBar {
            Text("\(r.name.prefix(1)) ready")
        } else if let s = store.soonest, let at = s.resetsAt {
            if store.liveNeedsSignIn && s.id == "claude" {
                Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(s.name.prefix(1)) \(Fmt.short(at.timeIntervalSince(store.now)))").monospacedDigit()
            } else {
                Text("\(s.name.prefix(1)) \(Fmt.short(at.timeIntervalSince(store.now)))").monospacedDigit()
            }
        } else {
            Image(systemName: "hourglass")
        }
    }
}

/// Hosts the first-run setup and hands over to the dashboard when it's done.
struct WelcomeWindow: View {
    let store: Store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    var body: some View {
        OnboardingView(store: store) {
            UserDefaults.standard.set(true, forKey: "onboarded")
            UserDefaults.standard.set(true, forKey: "dashboardSeen")
            openWindow(id: "dashboard")
            dismissWindow(id: "welcome")
        }
    }
}

extension Store {
    static let shared = Store()
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Store.shared.start()
    }

    // Show banners even when Reset's menu is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
