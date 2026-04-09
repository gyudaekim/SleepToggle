import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var manager: SleepManager
    var onDone: () -> Void

    @State private var watchedNetworks: [String] = AppSettings.shared.watchedNetworks
    @State private var batteryThreshold: Double = Double(AppSettings.shared.batteryThreshold)
    @State private var launchAtLogin: Bool = AppSettings.shared.launchAtLogin

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Button(action: {
                    save()
                    onDone()
                }) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Settings")
                    .font(.headline)
                Spacer()
                // Spacer for centering
                Text("Back  ")
                    .hidden()
            }

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // Wi-Fi Auto-Trigger
                    GroupBox("Wi-Fi Auto-Trigger") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Automatically prevent sleep when connected to:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(watchedNetworks, id: \.self) { ssid in
                                HStack {
                                    Image(systemName: "wifi")
                                    Text(ssid)
                                    Spacer()
                                    Button {
                                        watchedNetworks.removeAll { $0 == ssid }
                                        AppSettings.shared.watchedNetworks = watchedNetworks
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if watchedNetworks.isEmpty {
                                Text("No networks configured")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            if let currentSSID = manager.currentSSID {
                                Button {
                                    if !watchedNetworks.contains(currentSSID) {
                                        watchedNetworks.append(currentSSID)
                                        AppSettings.shared.watchedNetworks = watchedNetworks
                                    }
                                } label: {
                                    Label("Add current: \(currentSSID)", systemImage: "plus.circle")
                                }
                                .disabled(watchedNetworks.contains(currentSSID))
                            } else {
                                Text("No Wi-Fi connected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Battery Protection
                    GroupBox("Battery Protection") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Auto-disable when battery falls below:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Slider(value: $batteryThreshold, in: 5...50, step: 5)
                                Text("\(Int(batteryThreshold))%")
                                    .monospacedDigit()
                                    .frame(width: 40)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // General
                    GroupBox("General") {
                        Toggle("Launch at login", isOn: $launchAtLogin)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
    }

    private func save() {
        AppSettings.shared.watchedNetworks = watchedNetworks
        AppSettings.shared.batteryThreshold = Int(batteryThreshold)
        AppSettings.shared.launchAtLogin = launchAtLogin
        updateLaunchAtLogin(launchAtLogin)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}
