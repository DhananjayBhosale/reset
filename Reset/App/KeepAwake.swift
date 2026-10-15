import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import Observation

/// Keeps the Mac from idle-sleeping so auto-start and alerts run on time, without a separate app.
/// Only system idle sleep is blocked; the display still turns off on its normal schedule.
/// Closing the lid still sleeps the Mac unless it's connected to power and an external display.
@Observable
final class KeepAwake {
    enum Mode: String, CaseIterable, Identifiable {
        case off, pluggedIn, always
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: return "Off"
            case .pluggedIn: return "When plugged in"
            case .always: return "Always"
            }
        }
    }

    var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "keepAwake"); apply() }
    }
    private(set) var isHolding = false
    private(set) var onPower = true

    private var assertion: IOPMAssertionID = 0
    private var powerSource: CFRunLoopSource?

    init() {
        mode = Mode(rawValue: UserDefaults.standard.string(forKey: "keepAwake") ?? "") ?? .off
    }

    func start() {
        // Re-evaluate whenever the Mac is plugged in or unplugged.
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<KeepAwake>.fromOpaque(ctx).takeUnretainedValue().apply()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            powerSource = src
        }
        apply()
    }

    private func apply() {
        onPower = Self.isOnACPower()
        let want = mode == .always || (mode == .pluggedIn && onPower)
        if want && !isHolding {
            let reason = "Reset is keeping your Mac awake so usage alerts and auto-start run on time" as CFString
            if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertion) == kIOReturnSuccess {
                isHolding = true
            }
        } else if !want && isHolding {
            IOPMAssertionRelease(assertion)
            isHolding = false
        }
    }

    static func isOnACPower() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return true }
        return type == kIOPMACPowerKey
    }

    deinit { if isHolding { IOPMAssertionRelease(assertion) } }
}
