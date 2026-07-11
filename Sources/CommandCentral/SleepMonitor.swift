import AppKit
import Foundation

struct SleepEvent: Codable {
    var date: Date
    var type: String   // "sleep" | "wake"
}

/// Approximates sleep by watching when this Mac goes to sleep and wakes —
/// the longest overnight downtime is treated as last night's sleep.
final class SleepMonitor: ObservableObject {
    @Published private(set) var events: [SleepEvent] = []

    private var fileURL: URL { Storage.directory.appendingPathComponent("sleep.json") }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([SleepEvent].self, from: data) {
            events = decoded
        }
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil,
                           queue: .main) { [weak self] _ in
            self?.record("sleep")
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                           queue: .main) { [weak self] _ in
            self?.record("wake")
        }
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil,
                           queue: .main) { [weak self] _ in
            self?.record("sleep")
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil,
                           queue: .main) { [weak self] _ in
            self?.record("wake")
        }
        record("wake") // app launch counts as awake
    }

    private func record(_ type: String) {
        if let last = events.last, last.type == type,
           Date().timeIntervalSince(last.date) < 60 { return }
        events.append(SleepEvent(date: Date(), type: type))
        if events.count > 1000 {
            events.removeFirst(events.count - 1000)
        }
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Longest sleep→wake gap between `dayOffset-1` 18:00 and `dayOffset` 14:00.
    func nightSeconds(dayOffset: Int = 0) -> Int? {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: Date()),
              let windowEnd = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day),
              let previousDay = calendar.date(byAdding: .day, value: -1, to: day),
              let windowStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previousDay)
        else { return nil }

        let window = events.filter { $0.date >= windowStart && $0.date <= windowEnd }
        var best: Int?
        var sleepStart: Date?
        for event in window {
            if event.type == "sleep" {
                sleepStart = event.date
            } else if event.type == "wake", let start = sleepStart {
                let gap = Int(event.date.timeIntervalSince(start))
                if gap >= 3600, gap > (best ?? 0) { best = gap }
                sleepStart = nil
            }
        }
        return best
    }

    struct Night: Identifiable {
        let date: Date
        let seconds: Int?
        var id: Date { date }
    }

    func recentNights(_ count: Int) -> [Night] {
        let calendar = Calendar.current
        return (0..<count).map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return Night(date: calendar.startOfDay(for: day),
                         seconds: nightSeconds(dayOffset: offset))
        }
    }
}
