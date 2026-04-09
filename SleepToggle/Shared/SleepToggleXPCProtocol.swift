import Foundation

@objc protocol SleepToggleXPCProtocol {
    func enableSleepPrevention(reply: @escaping (Bool, String?) -> Void)
    func disableSleepPrevention(reply: @escaping (Bool, String?) -> Void)
    func getSleepPreventionStatus(reply: @escaping (Bool) -> Void)
}

let xpcServiceName = "com.sleeptoggle.helper"
