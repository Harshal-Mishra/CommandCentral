import AppKit
import Foundation

final class TimerManager: ObservableObject {
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var isRunning = false
    @Published private(set) var subject: String?

    /// Set by AppDelegate; receives the menu bar countdown text (nil clears it).
    var statusUpdate: (String?) -> Void = { _ in }
    /// Set by AppState; receives (subject, seconds) when focus time is completed.
    var onLog: (String, Int) -> Void = { _, _ in }
    /// Called when a countdown completes naturally.
    var onFinished: () -> Void = {}

    private var timer: Timer?
    private var totalSeconds = 0

    var remainingText: String {
        String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    func start(minutes: Int, subject: String? = nil) {
        logElapsed()
        cancelTimer()
        self.subject = subject
        totalSeconds = minutes * 60
        remainingSeconds = totalSeconds
        isRunning = true
        statusUpdate(remainingText)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        logElapsed()
        cancelTimer()
        subject = nil
        isRunning = false
        remainingSeconds = 0
        statusUpdate(nil)
    }

    private func tick() {
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            finish()
        } else {
            statusUpdate(remainingText)
        }
    }

    private func finish() {
        if let subject {
            onLog(subject, totalSeconds)
        }
        cancelTimer()
        subject = nil
        isRunning = false
        remainingSeconds = 0
        NSSound(named: "Glass")?.play()
        onFinished()
        statusUpdate("✅ Done")
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, !self.isRunning else { return }
            self.statusUpdate(nil)
        }
    }

    /// Logs partially-elapsed focus time when a session is stopped early.
    private func logElapsed() {
        guard isRunning, let subject else { return }
        let elapsed = totalSeconds - remainingSeconds
        if elapsed >= 60 {
            onLog(subject, elapsed)
        }
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }
}
