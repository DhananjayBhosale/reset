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
                let d = UserDefaults.standard
                if d.bool(forKey: "openDashboard") || !d.bool(forKey: "dashboardSeen") {
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
            Text("\(s.name.prefix(1)) \(Fmt.short(at.timeIntervalSince(store.now)))").monospacedDigit()
        } else {
            Image(systemName: "hourglass")
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
