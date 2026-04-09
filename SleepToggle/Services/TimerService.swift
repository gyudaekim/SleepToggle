import Foundation

class TimerService {
    var onTick: ((TimeInterval) -> Void)?
    var onExpire: (() -> Void)?

    private var endDate: Date?
    private var timer: Timer?

    var remaining: TimeInterval {
        guard let end = endDate else { return 0 }
        return max(0, end.timeIntervalSinceNow)
    }

    var isRunning: Bool { timer != nil }

    func start(duration: TimeInterval) {
        stop()
        endDate = Date().addingTimeInterval(duration)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let rem = self.remaining
            self.onTick?(rem)
            if rem <= 0 {
                self.onExpire?()
                self.stop()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        endDate = nil
    }
}
