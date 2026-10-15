import Foundation

/// "Start a window now" from a widget's button. The widget runs sandboxed and can't launch Claude Code, so it
/// posts a Darwin notification and the app, which can, does the start. Darwin notifications carry no data and
/// never leave the Mac; the name says which provider.
enum StartRequest {
    static func name(_ provider: String) -> String { "in.trak.reset.start." + provider }

    static func post(_ provider: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(name(provider) as CFString), nil, nil, true)
    }

    /// Calls `handler` on the main queue each time the named notification arrives, until it's released.
    final class Listener {
        let name: String
        private let handler: () -> Void

        init(name: String, handler: @escaping () -> Void) {
            self.name = name
            self.handler = handler
            let me = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), me, { _, observer, _, _, _ in
                guard let observer else { return }
                let l = Unmanaged<Listener>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { l.handler() }
            }, name as CFString, nil, .deliverImmediately)
        }

        deinit {
            CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
                                               CFNotificationName(name as CFString), nil)
        }
    }
}
