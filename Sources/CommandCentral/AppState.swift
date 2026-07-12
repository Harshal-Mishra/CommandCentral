import AppKit
import Combine
import Foundation

enum Storage {
    static var directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("CommandCentral", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

final class AppState: ObservableObject {
    let settings = AppSettings()
    let tasks = TaskStore()
    let timer = TimerManager()
    let links = LinkStore()
    let apps = AppScanner()
    let media = MediaController()
    let stats = SystemStats()
    let notes = NoteStore()
    let clipboard = ClipboardStore()
    let windows = WindowsManager()
    let home = HomeStore()
    let tracker = TimeTracker()
    let events = EventsStore()
    let location = LocationStore()
    let clocks = WorldClockStore()
    let alarms = AlarmStore()
    let sleep = SleepMonitor()
    let tabPrefs = TabPrefs()
    let journal = JournalStore()
    let custom = CustomCommandStore()
    let snips = SnipStore()
    lazy var weather = WeatherStore(location: location)
    lazy var quakes = QuakeStore(location: location)
    lazy var engine = CommandEngine(state: self)

    private var cancellables: Set<AnyCancellable> = []

    init() {
        timer.onLog = { [weak self] subject, seconds in
            self?.tracker.log(subject: subject, seconds: seconds)
        }
        timer.onFinished = {
            NotificationManager.shared.notify(title: "Focus session complete",
                                              body: "Nice work — your time was logged.")
        }
        settings.$idleAutoStopMinutes
            .sink { [tracker] minutes in tracker.idleLimitSeconds = minutes * 60 }
            .store(in: &cancellables)
        settings.$clipboardLimit
            .sink { [clipboard] limit in clipboard.setLimit(limit) }
            .store(in: &cancellables)
    }

    /// Set by AppDelegate; commands call these to drive the UI.
    var hidePalette: () -> Void = {}
    var showDashboard: () -> Void = {}
    var showDashboardTab: (DashboardTab) -> Void = { _ in }
    var showJournal: () -> Void = {}
    /// Set by AppDelegate; the palette reports its content size here so the
    /// panel can shrink/grow to fit, Spotlight-style.
    var paletteResize: (CGSize) -> Void = { _ in }

    /// Last tab the dashboard showed; lets the window controller restore
    /// the right monitors when the window reopens.
    var currentTab: DashboardTab = .home

    /// Captures a screenshot. Quick Markup copies handle everything in the
    /// overlay (clipboard + save + notification); the editor only opens
    /// when the capture asks for it.
    func startSnip(_ mode: SnipStore.Mode) {
        hidePalette()
        snips.capture(mode) { [weak self] url, openEditor in
            guard let self, let url else { return }
            if openEditor {
                NotificationManager.shared.notify(title: "Snip saved 📸",
                                                  body: "Copied to clipboard — opening the editor")
                self.snips.pendingEdit = url
                self.showDashboardTab(.snips)
            } else {
                NotificationManager.shared.notify(title: "Snip saved 📸",
                                                  body: "Copied to clipboard — it's in the Snips tab")
            }
        }
    }

    /// Runs only the pollers the visible tab actually needs. Pass nil when
    /// the dashboard window closes to stop them all.
    func updateMonitors(for tab: DashboardTab?) {
        let homeWidgets: Set<WidgetKind> = tab == .home ? Set(home.widgets.map(\.kind)) : []

        if tab == .system || homeWidgets.contains(.system) {
            stats.startMonitoring()
        } else {
            stats.stopMonitoring()
        }
        if tab == .media || homeWidgets.contains(.media) {
            media.startMonitoring()
        } else {
            media.stopMonitoring()
        }
        if tab == .windows {
            windows.startMonitoring()
        } else {
            windows.stopMonitoring()
        }
        // Weather & quakes stay on once started — they power alerts and only
        // refresh every 15 minutes.
        if tab != nil {
            weather.startMonitoring()
            quakes.startMonitoring()
        }
    }
}
