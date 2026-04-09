# SleepToggle — Handoff Document

## What This Is

A macOS menu bar app that prevents the Mac from sleeping when the laptop lid is closed. The user's primary use case is **phone tethering**: they connect to their phone's hotspot, close the lid, and need the laptop to stay awake.

The user is **not a developer**. They previously ran `sudo pmset -a disablesleep 1/0` manually in Terminal.

## Current State

The app **builds and runs** (`BUILD SUCCEEDED`). It shows a bolt icon in the menu bar and presents a popover panel with toggle, timer, Wi-Fi settings, battery info, and a settings page.

### What Works

- **Build system**: `xcodegen generate && xcodebuild -project SleepToggle.xcodeproj -scheme SleepToggle -configuration Debug build` succeeds cleanly.
- **Menu bar icon**: Appears as `bolt.slash.fill` (off) / `bolt.fill` (on). Uses `NSStatusItem` + `NSPopover` via `AppDelegate`.
- **Popover panel**: Does NOT dismiss when clicking inside (fixed by switching from `MenuBarExtra .window` to `NSPopover` with `.applicationDefined` behavior).
- **Settings inline navigation**: Settings page renders inside the same popover (no sheet). Back button returns to main view.
- **Wi-Fi delete button**: Works — uses `@State` array synced to `AppSettings` (UserDefaults).
- **Project generation**: `project.yml` with xcodegen. Two targets: `SleepToggle` (app) and `SleepToggleHelper` (tool, embedded at `Contents/Library/LaunchDaemons/`).

### What Needs Testing / May Not Work Yet

These features are **coded but not confirmed working end-to-end** by the user:

1. **One-time sudo setup flow** (`SleepController.setupPasswordlessSudo`): Creates `/etc/sudoers.d/sleeptoggle` via AppleScript `do shell script with administrator privileges`. After this, `sudo pmset` runs without a password. The setup screen appears when the file doesn't exist. **User has not yet confirmed they completed this flow.** If the sudoers rule has a syntax error, `sudo` will break for the user — test carefully. Run `visudo -cf /etc/sudoers.d/sleeptoggle` after creation to validate.

2. **Actual sleep prevention**: The toggle calls `sudo /usr/bin/pmset -a disablesleep 1` via `Process`. Verify with `pmset -g | grep SleepDisabled`. Then close the lid and confirm the Mac stays awake.

3. **Wi-Fi auto-trigger**: `WiFiMonitor` uses `CoreWLAN` (`CWWiFiClient.shared()`) + `CWEventDelegate` to detect SSID changes. **Requires Location Services permission** (`NSLocationWhenInUseUsageDescription` in Info.plist, `CLLocationManager.requestWhenInUseAuthorization()`). If the user denies location, `currentSSID()` returns nil and auto-trigger won't work. The entitlement `com.apple.developer.networking.wifi-info` is listed in project.yml but the entitlements file was cleared by xcodegen — you may need to re-add it.

4. **Battery monitor**: Uses `IOPSNotificationCreateRunLoopSource` + `IOPSCopyPowerSourcesInfo` from IOKit. Should fire callbacks on power source changes. Auto-disables sleep prevention when battery < threshold (default 20%) and not on AC.

5. **Timer**: `TimerService` uses a 1-second `Timer` with an end date. `timerRemaining` updates the UI. On expiry calls `disable()`. Not tested with actual timer completion.

6. **Launch at login**: Uses `SMAppService.mainApp.register()`. Should work on macOS 14+.

7. **Popover dismiss on outside click**: Currently `popover.behavior = .applicationDefined`, which means the popover does NOT auto-close when clicking outside. Consider adding an event monitor to close on outside click, or switch to `.transient` if the interior-click issue is truly fixed.

## What Was Tried and Abandoned

### Approach 1: Privileged Helper + XPC (abandoned)
The initial plan was to use `SMAppService.daemon(plistName:)` to register a LaunchDaemon helper that runs as root and executes `pmset` via XPC. This is the "correct" macOS architecture.

**Why abandoned**: Requires a paid Apple Developer ID ($99/year) for code signing and notarization. Without it, macOS refuses to register the daemon. The user is not a developer and doesn't have a Developer ID. The `SleepToggleHelper` target and its files (`main.swift`, `SleepHelperDelegate.swift`, `com.sleeptoggle.helper.plist`, `SleepToggleXPCProtocol.swift`) are still in the project but **unused by the current approach**. They can be removed or revived if the user gets a Developer ID.

### Approach 2: AppleScript every time (abandoned)
Used `do shell script "pmset -a disablesleep VALUE" with administrator privileges` for each toggle.

**Why abandoned**: Prompts for password/Touch ID on every single toggle. Unacceptable UX.

### Approach 3 (current): One-time sudoers + direct `sudo Process`
Creates `/etc/sudoers.d/sleeptoggle` with a NOPASSWD rule for `pmset -a disablesleep 1` and `pmset -a disablesleep 0`. One-time password prompt via AppleScript, then `Process(executableURL: /usr/bin/sudo)` runs without further auth.

### MenuBarExtra .window style (abandoned)
The initial UI used SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)`.

**Why abandoned**: Clicking any interactive element (button, slider, toggle) inside the panel caused it to dismiss. This is a known SwiftUI bug. Replaced with `AppDelegate` + `NSStatusItem` + `NSPopover` which does not have this issue.

### Swift 6 (abandoned)
Initially set `SWIFT_VERSION: "6.0"` in project.yml.

**Why abandoned**: Swift 6 strict concurrency produced many errors (`sending 'self' risks causing data races`, `static property is not concurrency-safe`). Switched to `SWIFT_VERSION: "5"` since concurrency safety isn't critical for this single-threaded UI app.

## Remaining Work

### Must Fix (bugs / incomplete flows)

1. **Test the one-time setup flow end-to-end.** Click the bolt icon, see the setup screen, click "Grant Permission", enter password. Verify `/etc/sudoers.d/sleeptoggle` exists and has correct content. Then toggle and verify `pmset -g | grep SleepDisabled` flips.

2. **Test lid-close behavior.** Toggle ON, close lid, confirm Mac stays awake (SSH in from another machine, or check `pmset -g` after reopening).

3. **Popover outside-click dismissal.** The popover currently stays open forever until you click the icon again. Add an `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])` in `AppDelegate` to close the popover when clicking outside.

4. **Wi-Fi entitlement.** The `com.apple.developer.networking.wifi-info` entitlement may be needed for `CWWiFiClient.interface()?.ssid()` to return a value. Check if SSID is nil even when connected. If so, re-add the entitlement to `SleepToggle/Resources/SleepToggle.entitlements`.

5. **Location permission UX.** If the user denies location, the Wi-Fi SSID will be nil. The Settings view shows "No Wi-Fi connected" which is misleading. Show "Location access required for Wi-Fi detection" instead, with a button to open System Settings.

6. **Cleanup on app quit.** `SleepManager.cleanup()` calls `disable()` which runs `sudo pmset -a disablesleep 0`. But if the app is force-killed, sleep stays prevented. Consider adding a periodic check or a launchd-based safety mechanism.

7. **SleepToggleHelper target is vestigial.** The XPC-based helper daemon target still builds and embeds in the app bundle. It adds ~90KB to the app and does nothing. Either remove the target from `project.yml` and delete `SleepToggleHelper/` or keep it dormant for a future Developer ID upgrade path.

### Nice to Have

8. **App icon.** Currently uses the default macOS app icon. Design or use an SF Symbol-based icon.

9. **Localization.** All strings are in English. The user speaks Korean. Consider localizing the UI.

10. **Notifications.** When battery protection auto-disables sleep, or when a Wi-Fi trigger fires, send a macOS notification so the user knows what happened.

11. **Dark/light mode icon adaptation.** The menu bar icon should look good in both. SF Symbols handle this automatically, but verify.

## File Map

```
SleepToggle/
  project.yml                              # xcodegen spec (run `xcodegen generate` after edits)
  SleepToggle.xcodeproj/                   # generated — do NOT edit directly, edit project.yml
  SleepToggle/
    SleepToggleApp.swift                   # @main App + AppDelegate (NSStatusItem + NSPopover)
    Views/
      StatusPanelView.swift                # Main popover: toggle, timer, info, setup screen
      SettingsView.swift                   # Inline settings: Wi-Fi networks, battery threshold, launch at login
    Models/
      AppSettings.swift                    # UserDefaults wrapper (watchedNetworks, batteryThreshold, launchAtLogin)
    Services/
      SleepManager.swift                   # @Observable central coordinator (toggle, timer, wifi, battery)
      XPCClient.swift                      # SleepController: sudoers setup + sudo pmset via Process (misnamed file, contains SleepController class)
      WiFiMonitor.swift                    # CoreWLAN + CoreLocation SSID monitoring
      BatteryMonitor.swift                 # IOKit IOPowerSources battery level + AC status
      TimerService.swift                   # Countdown timer with onTick/onExpire callbacks
    Shared/
      SleepToggleXPCProtocol.swift         # XPC protocol + service name constant (VESTIGIAL — only used by helper target)
    Resources/
      Info.plist                           # LSUIElement=true, NSLocationWhenInUseUsageDescription
      SleepToggle.entitlements             # Currently empty dict (may need wifi-info entitlement)
  SleepToggleHelper/                       # VESTIGIAL — privileged helper daemon (unused in current approach)
    main.swift
    SleepHelperDelegate.swift
    com.sleeptoggle.helper.plist
    SleepToggleHelper.entitlements
```

## Build & Run

```bash
cd /Users/gyudaekim/Projects/SleepToggle
xcodegen generate                          # regenerate .xcodeproj from project.yml
xcodebuild -project SleepToggle.xcodeproj -scheme SleepToggle -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/SleepToggle-*/Build/Products/Debug/SleepToggle.app
```

Or open `SleepToggle.xcodeproj` in Xcode and hit Run.

## Key Technical Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| Sleep mechanism | `sudo pmset -a disablesleep 1/0` | Only mechanism that reliably prevents lid-close sleep. IOPMAssertion explicitly does NOT prevent lid-close (per SDK headers). caffeinate is unreliable for lid-close on Apple Silicon. |
| Privilege escalation | One-time sudoers entry | No Developer ID available for LaunchDaemon code signing. AppleScript per-toggle was too annoying. |
| Menu bar UI | NSStatusItem + NSPopover | MenuBarExtra .window style dismissed on any click inside (SwiftUI bug). |
| Swift version | 5 | Swift 6 strict concurrency errors were not worth fixing for a single-user UI app. |
| Project generation | xcodegen | Easier to maintain than raw .xcodeproj. Edit project.yml, run `xcodegen generate`. |
| Settings storage | UserDefaults | Simple, sufficient. No database needed. |
| Wi-Fi detection | CoreWLAN + CoreLocation | CoreWLAN requires Location Services for SSID access since macOS 14. |
