import Foundation

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock, tasks, timer, media, calendar, system, links, notes, clipboard, hours, streak,
         weather, sun, worldclock, sleepw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .tasks: return "Tasks"
        case .timer: return "Focus Timer"
        case .media: return "Now Playing"
        case .calendar: return "Calendar"
        case .system: return "System"
        case .links: return "Quick Links"
        case .notes: return "Notes"
        case .clipboard: return "Clipboard"
        case .hours: return "Study Hours"
        case .streak: return "Streak"
        case .weather: return "Weather"
        case .sun: return "Sun"
        case .worldclock: return "World Clocks"
        case .sleepw: return "Sleep"
        }
    }

    var icon: String {
        switch self {
        case .clock: return "clock"
        case .tasks: return "checklist"
        case .timer: return "timer"
        case .media: return "music.note"
        case .calendar: return "calendar"
        case .system: return "cpu"
        case .links: return "link"
        case .notes: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .hours: return "hourglass"
        case .streak: return "flame"
        case .weather: return "cloud.sun"
        case .sun: return "sunrise"
        case .worldclock: return "globe"
        case .sleepw: return "bed.double"
        }
    }
}

struct WidgetConfig: Codable, Identifiable {
    var kind: WidgetKind
    var expanded = false
    var id: String { kind.rawValue }
}

/// Which widgets ("islands") the Home tab shows, in what order and size.
final class HomeStore: ObservableObject {
    @Published private(set) var widgets: [WidgetConfig] = []

    private var fileURL: URL { Storage.directory.appendingPathComponent("home.json") }

    private static let defaultLayout: [WidgetConfig] = [
        WidgetConfig(kind: .clock),
        WidgetConfig(kind: .hours),
        WidgetConfig(kind: .streak),
        WidgetConfig(kind: .tasks, expanded: true),
        WidgetConfig(kind: .timer),
        WidgetConfig(kind: .media),
        WidgetConfig(kind: .calendar, expanded: true),
        WidgetConfig(kind: .system, expanded: true),
    ]

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([WidgetConfig].self, from: data),
           !decoded.isEmpty {
            widgets = decoded
        } else {
            widgets = Self.defaultLayout
        }
    }

    var available: [WidgetKind] {
        let used = Set(widgets.map(\.kind))
        return WidgetKind.allCases.filter { !used.contains($0) }
    }

    func add(_ kind: WidgetKind) {
        guard !widgets.contains(where: { $0.kind == kind }) else { return }
        widgets.append(WidgetConfig(kind: kind))
        save()
    }

    func remove(_ kind: WidgetKind) {
        widgets.removeAll { $0.kind == kind }
        save()
    }

    func move(_ kind: WidgetKind, by offset: Int) {
        guard let index = widgets.firstIndex(where: { $0.kind == kind }) else { return }
        let target = index + offset
        guard widgets.indices.contains(target) else { return }
        widgets.swapAt(index, target)
        save()
    }

    func toggleSize(_ kind: WidgetKind) {
        guard let index = widgets.firstIndex(where: { $0.kind == kind }) else { return }
        widgets[index].expanded.toggle()
        save()
    }

    func resetLayout() {
        widgets = Self.defaultLayout
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(widgets) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
