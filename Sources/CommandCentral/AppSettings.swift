import SwiftUI

// MARK: - Choices

enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, purple, green, orange, pink, red

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: return Color(red: 0.38, green: 0.65, blue: 1.0)
        case .purple: return Color(red: 0.72, green: 0.54, blue: 1.0)
        case .green: return Color(red: 0.36, green: 0.84, blue: 0.55)
        case .orange: return Color(red: 1.0, green: 0.64, blue: 0.30)
        case .pink: return Color(red: 1.0, green: 0.52, blue: 0.76)
        case .red: return Color(red: 1.0, green: 0.46, blue: 0.44)
        }
    }
}

enum BackgroundChoice: String, CaseIterable, Identifiable {
    case deepBlue, graphite, forest, plum, midnight

    var id: String { rawValue }

    var name: String {
        switch self {
        case .deepBlue: return "Deep Blue"
        case .graphite: return "Graphite"
        case .forest: return "Forest"
        case .plum: return "Plum"
        case .midnight: return "Midnight"
        }
    }

    var colors: [Color] {
        switch self {
        case .deepBlue:
            return [Color(red: 0.05, green: 0.11, blue: 0.28),
                    Color(red: 0.03, green: 0.06, blue: 0.18),
                    Color(red: 0.01, green: 0.02, blue: 0.09)]
        case .graphite:
            return [Color(red: 0.16, green: 0.17, blue: 0.20),
                    Color(red: 0.10, green: 0.11, blue: 0.13),
                    Color(red: 0.05, green: 0.05, blue: 0.06)]
        case .forest:
            return [Color(red: 0.04, green: 0.19, blue: 0.14),
                    Color(red: 0.02, green: 0.11, blue: 0.09),
                    Color(red: 0.01, green: 0.04, blue: 0.03)]
        case .plum:
            return [Color(red: 0.18, green: 0.07, blue: 0.24),
                    Color(red: 0.11, green: 0.04, blue: 0.16),
                    Color(red: 0.04, green: 0.01, blue: 0.07)]
        case .midnight:
            return [Color(red: 0.04, green: 0.04, blue: 0.06),
                    Color(red: 0.02, green: 0.02, blue: 0.03),
                    .black]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Store

/// All user-tweakable preferences, persisted to UserDefaults. Side effects
/// that belong to other stores (tracker idle limit, clipboard size) are
/// wired up in AppState.
final class AppSettings: ObservableObject {
    @Published var tabLabels: Bool {
        didSet { defaults.set(tabLabels, forKey: "tabLabels") }
    }
    @Published var accent: AccentChoice {
        didSet {
            defaults.set(accent.rawValue, forKey: "accentColor")
            Theme.accent = accent.color
        }
    }
    @Published var background: BackgroundChoice {
        didSet {
            defaults.set(background.rawValue, forKey: "backgroundTheme")
            Theme.background = background
        }
    }
    @Published var showSeconds: Bool {
        didSet { defaults.set(showSeconds, forKey: "showSeconds") }
    }
    @Published var showBattery: Bool {
        didSet { defaults.set(showBattery, forKey: "showBattery") }
    }
    @Published var defaultTab: DashboardTab {
        didSet { defaults.set(defaultTab.rawValue, forKey: "defaultTab") }
    }
    /// Minutes of inactivity before the study stopwatch auto-stops; 0 = never.
    @Published var idleAutoStopMinutes: Int {
        didSet { defaults.set(idleAutoStopMinutes, forKey: "idleAutoStop") }
    }
    @Published var clipboardLimit: Int {
        didSet { defaults.set(clipboardLimit, forKey: "clipboardLimit") }
    }
    /// Global ⇧⌘S captures an area snip from anywhere.
    @Published var snipHotkey: Bool {
        didSet { defaults.set(snipHotkey, forKey: "snipHotkeyEnabled") }
    }

    private let defaults = UserDefaults.standard

    init() {
        tabLabels = defaults.bool(forKey: "tabLabels")
        accent = AccentChoice(rawValue: defaults.string(forKey: "accentColor") ?? "") ?? .blue
        background = BackgroundChoice(rawValue: defaults.string(forKey: "backgroundTheme") ?? "") ?? .deepBlue
        showSeconds = defaults.object(forKey: "showSeconds") as? Bool ?? true
        showBattery = defaults.object(forKey: "showBattery") as? Bool ?? true
        defaultTab = DashboardTab(rawValue: defaults.string(forKey: "defaultTab") ?? "") ?? .home
        idleAutoStopMinutes = defaults.object(forKey: "idleAutoStop") as? Int ?? 5
        clipboardLimit = defaults.object(forKey: "clipboardLimit") as? Int ?? 50
        snipHotkey = defaults.object(forKey: "snipHotkeyEnabled") as? Bool ?? true
        Theme.accent = accent.color
        Theme.background = background
    }
}
