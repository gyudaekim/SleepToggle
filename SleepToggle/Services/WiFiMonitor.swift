import Foundation
import CoreWLAN
import CoreLocation

class WiFiMonitor: NSObject, CWEventDelegate, CLLocationManagerDelegate {
    var onSSIDChanged: ((String?) -> Void)?

    private let wifiClient = CWWiFiClient.shared()
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func startMonitoring() {
        locationManager.requestWhenInUseAuthorization()

        wifiClient.delegate = self
        do {
            try wifiClient.startMonitoringEvent(with: .ssidDidChange)
        } catch {
            print("Failed to monitor Wi-Fi: \(error)")
        }
    }

    func stopMonitoring() {
        do {
            try wifiClient.stopMonitoringAllEvents()
        } catch {
            print("Failed to stop monitoring: \(error)")
        }
    }

    func currentSSID() -> String? {
        wifiClient.interface()?.ssid()
    }

    // MARK: - CWEventDelegate

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        let ssid = wifiClient.interface(withName: interfaceName)?.ssid()
        onSSIDChanged?(ssid)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways {
            onSSIDChanged?(currentSSID())
        }
    }
}
