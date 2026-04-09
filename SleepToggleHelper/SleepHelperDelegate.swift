import Foundation

class SleepHelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: SleepToggleXPCProtocol.self)
        newConnection.exportedObject = SleepHelperService()
        newConnection.resume()
        return true
    }
}

class SleepHelperService: NSObject, SleepToggleXPCProtocol {
    func enableSleepPrevention(reply: @escaping (Bool, String?) -> Void) {
        runPmset(enable: true, reply: reply)
    }

    func disableSleepPrevention(reply: @escaping (Bool, String?) -> Void) {
        runPmset(enable: false, reply: reply)
    }

    func getSleepPreventionStatus(reply: @escaping (Bool) -> Void) {
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
            let isDisabled = output.split(separator: "\n")
                .contains { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return trimmed.hasPrefix("SleepDisabled") && trimmed.hasSuffix("1")
                }
            reply(isDisabled)
        } catch {
            reply(false)
        }
    }

    private func runPmset(enable: Bool, reply: @escaping (Bool, String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", enable ? "1" : "0"]

        let pipe = Pipe()
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                reply(true, nil)
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                reply(false, errorMsg)
            }
        } catch {
            reply(false, error.localizedDescription)
        }
    }
}
