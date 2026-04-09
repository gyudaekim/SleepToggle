import Foundation

class SleepController {
    private static let sudoersFile = "/etc/sudoers.d/sleeptoggle"

    /// Check if passwordless sudo is already configured
    var isSetupComplete: Bool {
        FileManager.default.fileExists(atPath: Self.sudoersFile)
    }

    /// One-time setup: create sudoers entry (requires password once)
    func setupPasswordlessSudo(completion: @escaping (Bool, String?) -> Void) {
        let user = NSUserName()
        let rule = "\(user) ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"
        let script = """
        do shell script "echo '\(rule)' > /etc/sudoers.d/sleeptoggle && chmod 0440 /etc/sudoers.d/sleeptoggle" with administrator privileges
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let error {
                    let msg = error[NSAppleScript.errorMessage] as? String ?? "Setup failed"
                    DispatchQueue.main.async { completion(false, msg) }
                } else {
                    DispatchQueue.main.async { completion(true, nil) }
                }
            } else {
                DispatchQueue.main.async { completion(false, "Failed to create script") }
            }
        }
    }

    func enableSleepPrevention(completion: @escaping (Bool, String?) -> Void) {
        runPmset(enable: true, completion: completion)
    }

    func disableSleepPrevention(completion: @escaping (Bool, String?) -> Void) {
        runPmset(enable: false, completion: completion)
    }

    func getSleepPreventionStatus(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g"]

            let pipe = Pipe()
            process.standardOutput = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let isDisabled = output.split(separator: "\n").contains { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return trimmed.hasPrefix("SleepDisabled") && trimmed.hasSuffix("1")
                }
                DispatchQueue.main.async { completion(isDisabled) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    /// Run pmset via sudo (no password after setup)
    private func runPmset(enable: Bool, completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["/usr/bin/pmset", "-a", "disablesleep", enable ? "1" : "0"]

            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    DispatchQueue.main.async { completion(true, nil) }
                } else {
                    let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                    DispatchQueue.main.async { completion(false, msg) }
                }
            } catch {
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
            }
        }
    }
}
