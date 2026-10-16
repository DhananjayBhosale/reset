import Foundation
import Network
import Observation

/// Whether this Mac can reach the internet right now. Auto-start and Start now wait for it: overnight, a Mac on
/// battery or just waking often has no network, and each run then spends its 3 minutes and a try for nothing
/// (three such runs timed out on 10-16 between 12:55 and 1:46 AM).
@Observable
final class NetworkWatch {
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async { self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "reset.network"))
    }

    deinit { monitor.cancel() }
}
