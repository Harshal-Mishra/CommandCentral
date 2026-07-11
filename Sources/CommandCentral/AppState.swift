import AppKit
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
    lazy var weather = WeatherStore(location: location)
    lazy var quakes = QuakeStore(location: location)
    lazy var engine = CommandEngine(state: self)

    init() {
        timer.onLog = { [weak self] subject, seconds in
            self?.tracker.log(subject: subject, seconds: seconds)
        }
        timer.onFinished = {
            NotificationManager.shared.notify(title: "Focus session complete",
                                              body: "Nice work — your time was logged.")
        }
    }

    /// Set by AppDelegate; commands call these to drive the UI.
    var hidePalette: () -> Void = {}
    var showDashboard: () -> Void = {}
    var showDashboardTab: (DashboardTab) -> Void = { _ in }
    var showJournal: () -> Void = {}
}
