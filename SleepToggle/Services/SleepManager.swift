import Foundation
import Combine

@Observable
class SleepManager {
    var isActive = false
    var activeReason: ActiveReason = .none
    var timerRemaining: TimeInterval = 0
    var currentSSID: String?
    var batteryLevel: Int = 100
    var isOnACPower: Bool = true
    var error: String?
    var needsSetup = false
    var isSettingUp = false
    var onStateChanged: ((Bool) -> Void)?

    enum ActiveReason: Equatable {
        case none
        case manual
        case timer(duration: TimeInterval)
        case wifi(ssid: String)
    }

    private let sleepController = SleepController()
    private let timerService = TimerService()
    private var wifiMonitor: WiFiMonitor?
    private var batteryMonitor: BatteryMonitor?
    private let settings = AppSettings.shared

    init() {
        setupTimerCallback()
    }

    func setup() {
        needsSetup = !sleepController.isSetupComplete
        if !needsSetup {
            refreshStatus()
        }
        setupWiFiMonitor()
        setupBatteryMonitor()
    }

    func performSetup() {
        isSettingUp = true
        sleepController.setupPasswordlessSudo { [weak self] success, errorMsg in
            DispatchQueue.main.async {
                self?.isSettingUp = false
                if success {
                    self?.needsSetup = false
                    self?.refreshStatus()
                } else {
                    self?.error = errorMsg
                }
            }
        }
    }

    // MARK: - Manual Toggle

    func toggle() {
        if isActive {
            disable(reason: "Manual toggle off")
        } else {
            enable(reason: .manual)
        }
    }

    func enable(reason: ActiveReason) {
        sleepController.enableSleepPrevention { [weak self] success, errorMsg in
            DispatchQueue.main.async {
                if success {
                    self?.isActive = true
                    self?.activeReason = reason
                    self?.error = nil
                    self?.onStateChanged?(true)
                } else {
                    self?.error = errorMsg ?? "Failed to enable"
                }
            }
        }
    }

    func disable(reason: String) {
        timerService.stop()
        sleepController.disableSleepPrevention { [weak self] success, errorMsg in
            DispatchQueue.main.async {
                if success {
                    self?.isActive = false
                    self?.activeReason = .none
                    self?.timerRemaining = 0
                    self?.error = nil
                    self?.onStateChanged?(false)
                } else {
                    self?.error = errorMsg ?? "Failed to disable"
                }
            }
        }
    }

    // MARK: - Timer

    func enableWithTimer(duration: TimeInterval) {
        enable(reason: .timer(duration: duration))
        timerService.start(duration: duration)
    }

    private func setupTimerCallback() {
        timerService.onTick = { [weak self] remaining in
            DispatchQueue.main.async {
                self?.timerRemaining = remaining
            }
        }
        timerService.onExpire = { [weak self] in
            DispatchQueue.main.async {
                self?.disable(reason: "Timer expired")
            }
        }
    }

    // MARK: - Wi-Fi

    private func setupWiFiMonitor() {
        wifiMonitor = WiFiMonitor()
        wifiMonitor?.onSSIDChanged = { [weak self] ssid in
            DispatchQueue.main.async {
                self?.handleSSIDChange(ssid)
            }
        }
        wifiMonitor?.startMonitoring()
        currentSSID = wifiMonitor?.currentSSID()
    }

    private func handleSSIDChange(_ ssid: String?) {
        currentSSID = ssid
        let watchedNetworks = settings.watchedNetworks

        if let ssid, watchedNetworks.contains(ssid) {
            if !isActive {
                enable(reason: .wifi(ssid: ssid))
            }
        } else if case .wifi = activeReason {
            disable(reason: "Left watched Wi-Fi network")
        }
    }

    // MARK: - Battery

    private func setupBatteryMonitor() {
        batteryMonitor = BatteryMonitor()
        batteryMonitor?.onBatteryChanged = { [weak self] level, onAC in
            DispatchQueue.main.async {
                self?.handleBatteryChange(level: level, onAC: onAC)
            }
        }
        batteryMonitor?.startMonitoring()
        if let info = batteryMonitor?.currentInfo() {
            batteryLevel = info.level
            isOnACPower = info.isOnAC
        }
    }

    private func handleBatteryChange(level: Int, onAC: Bool) {
        batteryLevel = level
        isOnACPower = onAC

        if isActive && !onAC && level <= settings.batteryThreshold {
            disable(reason: "Battery below \(settings.batteryThreshold)%")
        }
    }

    // MARK: - Status

    func refreshStatus() {
        sleepController.getSleepPreventionStatus { [weak self] isDisabled in
            DispatchQueue.main.async {
                self?.isActive = isDisabled
                if isDisabled && self?.activeReason == .none {
                    self?.activeReason = .manual
                }
                self?.onStateChanged?(isDisabled)
            }
        }
    }

    func cleanup() {
        if isActive {
            disable(reason: "App quitting")
        }
    }
}
