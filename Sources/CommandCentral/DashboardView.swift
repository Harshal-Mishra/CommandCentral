import AppKit
import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case home, tracker, tasks, calendar, weather, time, map, media, windows, system, notes, clipboard, terminal, commands, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .tracker: return "Tracker"
        case .tasks: return "Tasks"
        case .calendar: return "Calendar"
        case .weather: return "Weather"
        case .time: return "Clocks"
        case .map: return "Map"
        case .media: return "Media"
        case .windows: return "Windows"
        case .system: return "System"
        case .notes: return "Notes"
        case .clipboard: return "Clipboard"
        case .terminal: return "Terminal"
        case .commands: return "Commands"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .tracker: return "chart.bar.xaxis"
        case .tasks: return "checklist"
        case .calendar: return "calendar"
        case .weather: return "cloud.sun"
        case .time: return "clock"
        case .map: return "map"
        case .media: return "music.note"
        case .windows: return "macwindow.on.rectangle"
        case .system: return "cpu"
        case .notes: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .terminal: return "terminal"
        case .commands: return "command"
        case .settings: return "gearshape"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var stats: SystemStats
    @EnvironmentObject private var tabPrefs: TabPrefs
    @EnvironmentObject private var alarms: AlarmStore
    @State private var tab: DashboardTab = .home

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider()
            content
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.gradient)
        .tint(Theme.accent)
        .overlay(alignment: .top) { alarmBanner }
        .onReceive(NotificationCenter.default.publisher(for: .openDashboardTab)) { note in
            if let raw = note.object as? String, let target = DashboardTab(rawValue: raw) {
                tab = target
            }
        }
        .onReceive(tabPrefs.$hidden) { _ in
            if !tabPrefs.isVisible(tab) { tab = .home }
        }
    }

    @ViewBuilder
    private var alarmBanner: some View {
        if let alarm = alarms.firing {
            HStack(spacing: 12) {
                Image(systemName: "alarm.waves.left.and.right.fill")
                    .font(.system(size: 18))
                Text("\(alarm.timeText) — \(alarm.label)")
                    .font(.system(size: 14, weight: .semibold))
                Button("Dismiss") { alarms.dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.25))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Theme.flame.gradient, in: Capsule())
            .foregroundStyle(.white)
            .shadow(radius: 12)
            .padding(.top, 14)
        }
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .firstTextBaseline) {
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                if let battery = stats.battery {
                    Label(battery, systemImage: "battery.75percent")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(context.date, format: .dateTime.hour().minute().second())
                    .font(.system(size: 22, weight: .light).monospacedDigit())
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabPrefs.visibleTabs) { item in
                        Button {
                            tab = item
                        } label: {
                            Label(item.title, systemImage: item.icon)
                                .font(.system(size: 12, weight: tab == item ? .semibold : .regular))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(tab == item ? Theme.accent.opacity(0.28) : .clear,
                                            in: Capsule())
                                .foregroundStyle(tab == item ? .white : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 14)
            }
            // Every tab — even hidden ones — stays reachable here.
            Menu {
                ForEach(tabPrefs.orderedTabs) { item in
                    Button {
                        tab = item
                    } label: {
                        Label(item.title + (tabPrefs.isVisible(item) ? "" : "  (hidden)"),
                              systemImage: item.icon)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("All tabs")
            .padding(.trailing, 14)
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home: HomeView()
        case .tracker: TrackerTabView()
        case .tasks: TasksTabView()
        case .calendar: CalendarTabView()
        case .weather: WeatherTabView()
        case .time: TimeTabView()
        case .map: MapTabView()
        case .media: MediaTabView()
        case .windows: WindowsView()
        case .system: SystemTabView()
        case .notes: NotesView()
        case .clipboard: ClipboardView()
        case .terminal: TerminalTabView()
        case .commands: CommandsTabView()
        case .settings: SettingsTabView()
        }
    }
}

extension Notification.Name {
    static let openDashboardTab = Notification.Name("openDashboardTab")
}

// MARK: - Simple tabs

struct TasksTabView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            TasksCard()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 14) {
                TimerCard()
                CalendarCard()
                Spacer()
            }
            .frame(width: 320)
        }
    }
}

struct CalendarTabView: View {
    @EnvironmentObject private var events: EventsStore

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CalendarCard(cellSize: 46)
                .frame(maxWidth: 620)
            VStack(spacing: 14) {
                upcomingCard
                TimerCard()
                Spacer()
            }
            .frame(width: 330)
        }
        .frame(maxWidth: .infinity)
        .onAppear { events.loadIfAuthorized() }
    }

    private var upcomingCard: some View {
        Card(title: "Upcoming (7 days)", systemImage: "calendar.badge.clock",
             trailing: events.isAuthorized ? "\(events.events.count)" : nil) {
            if events.isAuthorized {
                if events.events.isEmpty {
                    Text("No events in the next week 🎉")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(events.events) { event in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(event.color)
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(event.title)
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                        Text(eventTimeText(event))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 7))
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
            } else if events.status == .denied || events.status == .restricted {
                Text("Calendar access was denied. Enable it in System Settings → Privacy & Security → Calendars, then reopen this tab.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Show your real macOS Calendar events here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Connect Calendar") { events.connect() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func eventTimeText(_ event: EventItem) -> String {
        let day = event.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        if event.isAllDay { return "\(day) · all day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(day) · \(start)–\(end)"
    }
}

struct MediaTabView: View {
    var body: some View {
        VStack(spacing: 14) {
            MediaCard()
                .frame(width: 460)
            Text("Controls Spotify or Apple Music directly when running (allow the Automation prompt to see track info). With neither open, the buttons act as hardware media keys.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 440)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
