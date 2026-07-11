import AppKit
import Foundation

// MARK: - World clocks

final class WorldClockStore: ObservableObject {
    @Published private(set) var zones: [String] = []

    init() {
        zones = UserDefaults.standard.stringArray(forKey: "worldClocks")
            ?? [TimeZone.current.identifier, "Europe/London", "America/New_York", "Asia/Tokyo"]
    }

    func add(_ identifier: String) {
        guard TimeZone(identifier: identifier) != nil, !zones.contains(identifier) else { return }
        zones.append(identifier)
        save()
    }

    func remove(_ identifier: String) {
        zones.removeAll { $0 == identifier }
        save()
    }

    static func cityName(_ identifier: String) -> String {
        (identifier.components(separatedBy: "/").last ?? identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    static func matches(_ query: String) -> [String] {
        let q = query.lowercased()
        guard q.count >= 2 else { return [] }
        return TimeZone.knownTimeZoneIdentifiers
            .filter { $0.lowercased().contains(q) }
            .prefix(6)
            .map { $0 }
    }

    private func save() {
        UserDefaults.standard.set(zones, forKey: "worldClocks")
    }
}

// MARK: - Alarms

struct Alarm: Codable, Identifiable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var label: String
    var enabled = true
    var lastFired: Date?

    var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

final class AlarmStore: ObservableObject {
    @Published private(set) var alarms: [Alarm] = []
    @Published private(set) var firing: Alarm?

    private var checkTimer: Timer?
    private var soundTimer: Timer?
    private var soundCount = 0

    private var fileURL: URL { Storage.directory.appendingPathComponent("alarms.json") }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Alarm].self, from: data) {
            alarms = decoded
        }
    }

    func start() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(checkTimer!, forMode: .common)
    }

    func add(hour: Int, minute: Int, label: String) {
        alarms.append(Alarm(hour: hour, minute: minute,
                            label: label.isEmpty ? "Alarm" : label))
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        save()
    }

    func remove(_ id: UUID) {
        alarms.removeAll { $0.id == id }
        save()
    }

    func toggle(_ id: UUID) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[index].enabled.toggle()
        save()
    }

    func dismiss() {
        firing = nil
        soundTimer?.invalidate()
        soundTimer = nil
    }

    private func check() {
        let now = Date()
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        for index in alarms.indices {
            let alarm = alarms[index]
            guard alarm.enabled,
                  alarm.hour == components.hour,
                  alarm.minute == components.minute else { continue }
            if let last = alarm.lastFired, now.timeIntervalSince(last) < 120 { continue }
            alarms[index].lastFired = now
            save()
            fire(alarms[index])
            break
        }
    }

    private func fire(_ alarm: Alarm) {
        firing = alarm
        soundCount = 0
        soundTimer?.invalidate()
        soundTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            NSSound(named: "Blow")?.play()
            self.soundCount += 1
            if self.soundCount > 30 { self.dismiss() }
        }
        RunLoop.main.add(soundTimer!, forMode: .common)
        NSSound(named: "Blow")?.play()
        NotificationManager.shared.notify(title: "⏰ \(alarm.timeText)", body: alarm.label)
        NotificationCenter.default.post(name: .alarmFired, object: nil)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(alarms) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
