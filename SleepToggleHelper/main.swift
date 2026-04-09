import Foundation

let delegate = SleepHelperDelegate()
let listener = NSXPCListener(machServiceName: xpcServiceName)
listener.delegate = delegate
listener.resume()

RunLoop.current.run()
