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

---

## Code Review & Fixes (2026-04-12)

A comprehensive code review was run against the initial commit using 9 parallel reviewers (correctness, testing, maintainability, project-standards, security, reliability, adversarial, agent-native, learnings-researcher). This section documents what was found, what was fixed, what was tried, and what remains.

### What Was Fixed

These changes are uncommitted in the working tree. Run `xcodegen generate` after committing to regenerate the `.xcodeproj`.

**1. BatteryMonitor use-after-free (BatteryMonitor.swift)**
- **Problem**: No `deinit`. If `BatteryMonitor` is deallocated while its CFRunLoopSource is still registered, the callback fires into freed memory.
- **Fix**: Added `deinit { stopMonitoring() }`.

**2. Battery maxCapacity=0 false low-battery trigger (BatteryMonitor.swift:50)**
- **Problem**: If IOKit returns `maxCapacity=0` (rare, third-party batteries), `(capacity * 100) / maxCapacity` would yield 0, which triggers the low-battery auto-disable even though battery state is unknown.
- **Fix**: Changed fallback from `0` to `100`. Unknown battery = assume full = don't trigger protection.

**3. Sudoers rule overly broad (SleepController.swift:22)**
- **Problem**: Rule used `ALL=(ALL)` allowing run-as any user. Only root is needed for pmset.
- **Fix**: Changed to `ALL=(root)`.

**4. File rename: XPCClient.swift -> SleepController.swift**
- **Problem**: File was named `XPCClient.swift` but contained `class SleepController` (leftover from the abandoned XPC approach).
- **Fix**: Renamed to match the class it contains.

**5. Sudoers validation with visudo (SleepController.swift:22-27)**
- **Problem**: The old setup wrote directly to `/etc/sudoers.d/sleeptoggle` with no syntax validation. An invalid rule would break all `sudo` system-wide.
- **Fix**: Setup now writes to `/tmp/sleeptoggle.sudoers` first, validates with `visudo -cf`, then copies to `/etc/sudoers.d/` only if valid. Temp file is always cleaned up.
- **What was considered**: Running `visudo -cf` after writing to `/etc/sudoers.d/` directly, but that's dangerous — the broken file is already in place if validation fails. The temp-file-then-move approach ensures the sudoers directory is never touched with invalid content.

**6. Username shell injection prevention (SleepController.swift:15-20)**
- **Problem**: `NSUserName()` was interpolated directly into a single-quoted AppleScript shell command. A username containing `'` would break quoting.
- **Fix**: Added validation that username only contains `[a-zA-Z0-9._-]` before building the rule. If invalid, setup fails with a clear error.
- **What was considered**: Shell-escaping the username (replacing `'` with `'\''`), but validation is simpler and more robust — macOS usernames shouldn't contain special chars anyway.

**7. Synchronous cleanup on app exit (SleepController.swift:53-66, SleepManager.swift:189-191)**
- **Problem**: `cleanup()` called `disable()` which dispatches async to a background queue, then dispatches the completion to the main queue. If the app exits before the chain completes, `pmset -a disablesleep 0` never runs. This was virtually guaranteed to happen since `applicationWillTerminate` is synchronous.
- **Fix**: Added `disableSleepPreventionSync()` to `SleepController` — runs `sudo pmset -a disablesleep 0` synchronously, blocking until the process exits. `cleanup()` now calls this instead of the async path.
- **What was considered**: Using `DispatchSemaphore` in the existing async path, but that deadlocks because the completion dispatches to the main queue which is already blocked by the semaphore wait. A dedicated sync method avoids the issue entirely.

**8. Sudoers recovery on failure (SleepManager.swift:78, 96, 102-106)**
- **Problem**: If the sudoers file was deleted or corrupted after initial setup, every enable/disable call would fail, but the app would never re-show the setup screen because `needsSetup` was only set once at launch.
- **Fix**: Added `checkSetupValidity()` called on enable/disable failure. If the sudoers file no longer exists, `needsSetup` is set back to `true`, re-showing the setup screen.

**9. Removed vestigial XPC helper (project.yml, SleepToggleHelper/, SleepToggle/Shared/)**
- **Problem**: The entire `SleepToggleHelper` target, its source files, plist, entitlements, and the shared `SleepToggleXPCProtocol.swift` were still in the project from the abandoned XPC approach. Added ~90KB to the app bundle and confused the codebase.
- **Fix**: Deleted `SleepToggleHelper/` directory, `SleepToggle/Shared/` directory, removed the helper target + dependency + postBuildScript from `project.yml`. Net -235 lines.

### What Remains (5 items, ordered by priority)

These are real issues found during review. Each has been verified by at least one reviewer with confidence >= 0.72. None are blocking for basic usage, but all should be addressed.

**R1. App crash / force-quit leaves sleep permanently disabled**
- **Severity**: P1 — user's battery drains if they force-quit while sleep is prevented
- **File**: `SleepToggleApp.swift` (app lifecycle)
- **Problem**: `applicationWillTerminate` calls `cleanup()` which now works for graceful exits. But `SIGKILL` (force-quit, system shutdown) skips `applicationWillTerminate` entirely. Sleep stays disabled until the user manually runs `pmset -a disablesleep 0`.
- **Suggested approach**: Write a flag to disk (e.g., `~/.sleeptoggle_active`) when sleep prevention is enabled, remove it on disable. On app launch, if the flag exists but sleep is not expected to be active, run disable. This handles crash recovery.
- **Why not done yet**: Needs a design decision about where to store the flag and whether to also handle the "app was uninstalled" case.

**R2. Process.waitUntilExit() blocks without timeout**
- **Severity**: P1 — if `pmset` or `sudo` hangs, the background thread blocks forever
- **File**: `SleepController.swift:79` (runPmset), also `getSleepPreventionStatus`
- **Problem**: Both `runPmset` and `getSleepPreventionStatus` call `process.waitUntilExit()` with no timeout. If `pmset` hangs (e.g., system under heavy load, sudo misconfigured), the thread is consumed permanently.
- **Suggested approach**: Use `DispatchSemaphore` with a timeout:
  ```swift
  let sem = DispatchSemaphore(value: 0)
  process.terminationHandler = { _ in sem.signal() }
  try process.run()
  if sem.wait(timeout: .now() + 10) == .timedOut {
      process.terminate()
      // report timeout error
  }
  ```
- **Why not done yet**: Changing from `waitUntilExit()` to `terminationHandler` changes the control flow. The `readDataToEndOfFile()` call after `waitUntilExit` also needs to be coordinated — reading before the process exits can block or return partial data.

**R3. Wi-Fi monitoring fails silently without location permission**
- **Severity**: P2 — user sees "No Wi-Fi connected" when the real issue is missing permission
- **File**: `WiFiMonitor.swift:20`, `SettingsView.swift`
- **Problem**: `startMonitoring()` catches the CoreWLAN error and prints to console. The user never sees it. `currentSSID()` returns nil, and the UI shows "No Wi-Fi connected" — misleading when connected but permission-denied.
- **Suggested approach**:
  1. In `WiFiMonitor`, expose a `var monitoringFailed: Bool` or propagate the error via callback
  2. In `SettingsView`, check `CLLocationManager.authorizationStatus`. If denied, show "Location access required for Wi-Fi detection" with a button: `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)`
- **Why not done yet**: Requires UI changes and a decision about how prominently to surface the error.

**R4. No test infrastructure**
- **Severity**: P2 — all critical paths are untested
- **File**: `project.yml` (no test target)
- **Problem**: Zero test files, zero test targets. Critical paths that need tests:
  - `SleepManager` state machine (enable/disable/timer/wifi/battery transitions)
  - `AppSettings` battery threshold default logic
  - `SleepController` pmset output parsing (`getSleepPreventionStatus`)
  - Timer expiry and callback ordering
- **Suggested approach**: Add a `SleepToggleTests` target to `project.yml`. Start with `SleepManager` state transitions since they're pure logic once the `SleepController` is mocked. The IOKit/CoreWLAN code is hard to unit test (system APIs), so focus on the coordinator and parsing logic.
- **Why not done yet**: Needs the xcodegen test target setup and a decision on mocking strategy.

**R5. Concurrent enable/disable race condition**
- **Severity**: P2 — UI state can diverge from system state under rapid toggling
- **File**: `SleepManager.swift:68-100`
- **Problem**: `enable()` and `disable()` both dispatch async work without mutual exclusion. If the user clicks toggle while a battery/wifi event also triggers a state change, two concurrent `pmset` calls execute. The last completion handler to reach the main queue wins, but the system state may not match.
- **Suggested approach**: Add an `isTransitioning` flag checked before dispatching enable/disable. Or use a serial `DispatchQueue` for all state mutations:
  ```swift
  private let stateQueue = DispatchQueue(label: "com.sleeptoggle.state")
  ```
  Route all enable/disable/status through this queue.
- **Why not done yet**: Requires restructuring the async flow. The current code dispatches to `.global(qos: .userInitiated)` for the process, then back to `.main` for state updates. Adding a serial queue in between needs care to avoid deadlocks.

### Updated File Map

```
SleepToggle/
  project.yml                              # xcodegen spec — single target now (helper removed)
  SleepToggle.xcodeproj/                   # generated — STALE, run `xcodegen generate` to update
  HANDOFF.md                               # this file
  SleepToggle/
    SleepToggleApp.swift                   # @main App + AppDelegate (NSStatusItem + NSPopover)
    Views/
      StatusPanelView.swift                # Main popover: toggle, timer, info, setup screen
      SettingsView.swift                   # Inline settings: Wi-Fi networks, battery threshold, launch at login
    Models/
      AppSettings.swift                    # UserDefaults wrapper (watchedNetworks, batteryThreshold, launchAtLogin)
    Services/
      SleepManager.swift                   # @Observable central coordinator (toggle, timer, wifi, battery)
      SleepController.swift                # Sudoers setup + sudo pmset via Process (renamed from XPCClient.swift)
      WiFiMonitor.swift                    # CoreWLAN + CoreLocation SSID monitoring
      BatteryMonitor.swift                 # IOKit IOPowerSources battery level + AC status
      TimerService.swift                   # Countdown timer with onTick/onExpire callbacks
    Resources/
      Info.plist                           # LSUIElement=true, NSLocationWhenInUseUsageDescription
      SleepToggle.entitlements             # Currently empty dict (may need wifi-info entitlement)
```

### Build After Review Changes

```bash
cd /Users/gyudaekim/Projects/SleepToggle
xcodegen generate                          # REQUIRED — project.yml changed, file renamed, files deleted
xcodebuild -project SleepToggle.xcodeproj -scheme SleepToggle -configuration Debug build
```
