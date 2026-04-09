import SwiftUI

struct StatusPanelView: View {
    @Bindable var manager: SleepManager
    weak var appDelegate: AppDelegate?
    @State private var currentTab: Tab = .main

    enum Tab {
        case main
        case settings
    }

    var body: some View {
        VStack(spacing: 0) {
            if manager.needsSetup {
                setupView
            } else if currentTab == .main {
                mainView
            } else {
                settingsView
            }
        }
        .frame(width: 300)
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            Text("Initial Setup Required")
                .font(.headline)

            Text("SleepToggle needs one-time permission to control sleep settings. After this, no password will be needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if manager.isSettingUp {
                ProgressView()
                    .controlSize(.small)
                Text("Setting up...")
                    .font(.caption)
            } else {
                Button(action: { manager.performSetup() }) {
                    Label("Grant Permission", systemImage: "key")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }

            if let error = manager.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }

    // MARK: - Main View

    private var mainView: some View {
        VStack(spacing: 12) {
            // Header with status
            HStack {
                Image(systemName: manager.isActive ? "bolt.fill" : "bolt.slash.fill")
                    .font(.title2)
                    .foregroundStyle(manager.isActive ? .yellow : .secondary)
                Text(manager.isActive ? "Sleep Prevented" : "Normal Sleep")
                    .font(.headline)
                Spacer()
            }

            // Active reason
            if manager.isActive {
                HStack {
                    Text(reasonText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            Divider()

            // Toggle button
            Button(action: { manager.toggle() }) {
                Label(
                    manager.isActive ? "Allow Sleep" : "Prevent Sleep",
                    systemImage: manager.isActive ? "moon.zzz" : "bolt.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            // Timer presets
            if !manager.isActive {
                HStack(spacing: 8) {
                    TimerButton(label: "30m", duration: 30 * 60, manager: manager)
                    TimerButton(label: "2h", duration: 2 * 3600, manager: manager)
                    TimerButton(label: "4h", duration: 4 * 3600, manager: manager)
                    TimerButton(label: "8h", duration: 8 * 3600, manager: manager)
                }
            }

            // Timer remaining
            if manager.timerRemaining > 0 {
                HStack {
                    Image(systemName: "timer")
                    Text(formatTime(manager.timerRemaining))
                        .monospacedDigit()
                    Spacer()
                    Button("Cancel Timer") {
                        manager.disable(reason: "Timer cancelled")
                    }
                    .controlSize(.small)
                }
                .font(.caption)
            }

            Divider()

            // Info row
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                    Text(manager.currentSSID ?? "No Wi-Fi")
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: batteryIcon)
                    Text("\(manager.batteryLevel)%")
                    if manager.isOnACPower {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Error
            if let error = manager.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                        .lineLimit(2)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.red)
            }

            Divider()

            // Footer
            HStack {
                Button(action: { currentTab = .settings }) {
                    Label("Settings", systemImage: "gear")
                }
                .controlSize(.small)
                Spacer()
                Button("Quit") {
                    manager.cleanup()
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .padding()
    }

    // MARK: - Settings View (inline)

    private var settingsView: some View {
        SettingsView(manager: manager, onDone: { currentTab = .main })
    }

    // MARK: - Helpers

    private var reasonText: String {
        switch manager.activeReason {
        case .none: return ""
        case .manual: return "Manually enabled"
        case .timer(let duration):
            return "Timer: \(formatTime(duration))"
        case .wifi(let ssid):
            return "Auto: connected to \(ssid)"
        }
    }

    private var batteryIcon: String {
        switch manager.batteryLevel {
        case 0..<25: return "battery.25percent"
        case 25..<50: return "battery.50percent"
        case 50..<75: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct TimerButton: View {
    let label: String
    let duration: TimeInterval
    let manager: SleepManager

    var body: some View {
        Button(label) {
            manager.enableWithTimer(duration: duration)
        }
        .controlSize(.small)
    }
}
