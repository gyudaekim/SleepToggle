import Foundation
import IOKit.ps

struct BatteryInfo {
    let level: Int
    let isOnAC: Bool
}

class BatteryMonitor {
    var onBatteryChanged: ((Int, Bool) -> Void)?

    private var runLoopSource: CFRunLoopSource?

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            if let info = monitor.currentInfo() {
                monitor.onBatteryChanged?(info.level, info.isOnAC)
            }
        }, context)?.takeRetainedValue()

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    func stopMonitoring() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
    }

    func currentInfo() -> BatteryInfo? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              let source = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?.takeUnretainedValue() as? [String: Any] else {
            return nil
        }

        let capacity = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int ?? 100
        let level = maxCapacity > 0 ? (capacity * 100) / maxCapacity : 100
        let powerSource = desc[kIOPSPowerSourceStateKey] as? String ?? ""
        let isOnAC = powerSource == kIOPSACPowerValue

        return BatteryInfo(level: level, isOnAC: isOnAC)
    }
}
