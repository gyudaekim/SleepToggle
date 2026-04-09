import Foundation

class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let watchedNetworks = "watchedNetworks"
        static let batteryThreshold = "batteryThreshold"
        static let launchAtLogin = "launchAtLogin"
    }

    var watchedNetworks: [String] {
        get { defaults.stringArray(forKey: Keys.watchedNetworks) ?? [] }
        set { defaults.set(newValue, forKey: Keys.watchedNetworks) }
    }

    var batteryThreshold: Int {
        get {
            let val = defaults.integer(forKey: Keys.batteryThreshold)
            return val == 0 ? 20 : val
        }
        set { defaults.set(newValue, forKey: Keys.batteryThreshold) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    func addWatchedNetwork(_ ssid: String) {
        var networks = watchedNetworks
        if !networks.contains(ssid) {
            networks.append(ssid)
            watchedNetworks = networks
        }
    }

    func removeWatchedNetwork(_ ssid: String) {
        var networks = watchedNetworks
        networks.removeAll { $0 == ssid }
        watchedNetworks = networks
    }
}
