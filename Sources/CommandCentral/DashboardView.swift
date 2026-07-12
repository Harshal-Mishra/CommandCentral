import AppKit
import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case home, tracker, tasks, calendar, weather, time, map, media, windows, system, notes, clipboard, terminal, commands, snips, settings

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
        case .snips: return "Snips"
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
        case .snips: return "scissors"
        case .settings: return "gearshape"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tabPrefs: TabPrefs
    @EnvironmentObject private var alarms: AlarmStore
    @EnvironmentObject private var home: HomeStore
    @State private var tab: DashboardTab = .home
    @State private var didApplyDefaultTab = false
    @State private var tabScroll = ScrollPosition()
    @State private var tabOverflow = TabOverflow()

    private struct TabOverflow: Equatable {
        var canLeft = false
        var canRight = false
        var offset: CGFloat = 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider()
            content
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Retheming: Theme.accent/background are globals, so force the whole
        // subtree to rebuild when they change.
        .id("theme-\(settings.accent.rawValue)-\(settings.background.rawValue)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settings.background.gradient)
        .tint(settings.accent.color)
        .overlay(alignment: .top) { alarmBanner }
        .onReceive(NotificationCenter.default.publisher(for: .openDashboardTab)) { note in
            if let raw = note.object as? String, let target = DashboardTab(rawValue: raw) {
                select(target)
            }
        }
        .onReceive(tabPrefs.$hidden) { _ in
            if !tabPrefs.isVisible(tab) { select(.home) }
        }
        .onReceive(home.$widgets) { _ in
            if tab == .home { state.updateMonitors(for: .home) }
        }
        .onAppear {
            if !didApplyDefaultTab {
                didApplyDefaultTab = true
                if tabPrefs.isVisible(settings.defaultTab) { tab = settings.defaultTab }
            }
            state.currentTab = tab
            state.updateMonitors(for: tab)
        }
        .onChange(of: tab) {
            state.currentTab = tab
            state.updateMonitors(for: tab)
        }
    }

    private func select(_ target: DashboardTab) {
        withAnimation(.snappy(duration: 0.22)) { tab = target }
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
        TimelineView(.periodic(from: clockStart, by: settings.showSeconds ? 1 : 60)) { context in
            HStack(alignment: .firstTextBaseline) {
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                if settings.showBattery {
                    BatteryBadge()
                }
                Text(context.date, format: settings.showSeconds
                     ? .dateTime.hour().minute().second()
                     : .dateTime.hour().minute())
                    .font(.system(size: 22, weight: .light).monospacedDigit())
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    /// Without seconds the clock only re-renders on real minute boundaries.
    private var clockStart: Date {
        guard !settings.showSeconds else { return .now }
        return Calendar.current.nextDate(after: .now,
                                         matching: DateComponents(second: 0),
                                         matchingPolicy: .nextTime) ?? .now
    }

    // Icon pills (optionally with names, per Settings). If the row outgrows
    // the window it scrolls — trackpad swipe or the edge chevrons.
    private var tabBar: some View {
        HStack(spacing: 6) {
            if tabOverflow.canLeft {
                chevron("chevron.left") { scrollTabs(-260) }
                    .padding(.leading, 8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(tabPrefs.visibleTabs) { item in
                        TabPill(item: item,
                                isSelected: tab == item,
                                alwaysLabel: settings.tabLabels) { select(item) }
                            .id(item)
                    }
                }
                .scrollTargetLayout()
                .padding(.leading, 14)
                .padding(.vertical, 2)
            }
            .scrollPosition($tabScroll)
            .onScrollGeometryChange(for: TabOverflow.self) { geo in
                TabOverflow(canLeft: geo.contentOffset.x > 4,
                            canRight: geo.contentOffset.x + geo.containerSize.width
                                      < geo.contentSize.width - 4,
                            offset: geo.contentOffset.x)
            } action: { _, new in
                tabOverflow = new
            }
            .onChange(of: tab) {
                withAnimation(.snappy(duration: 0.22)) {
                    tabScroll.scrollTo(id: tab)
                }
            }
            if tabOverflow.canRight {
                chevron("chevron.right") { scrollTabs(260) }
            }
            // Every tab — even hidden ones — stays reachable here.
            Menu {
                ForEach(tabPrefs.orderedTabs) { item in
                    Button {
                        select(item)
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
        .padding(.bottom, 8)
    }

    private func chevron(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 24)
                .background(Color.white.opacity(0.06), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Scroll tabs")
    }

    private func scrollTabs(_ delta: CGFloat) {
        withAnimation(.snappy(duration: 0.25)) {
            tabScroll.scrollTo(x: max(0, tabOverflow.offset + delta))
        }
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
        case .snips: SnipsTabView()
        case .settings: SettingsTabView()
        }
    }
}

/// One tab in the bar. Icon-only by default (the selected one stretches to
/// show its title); with `alwaysLabel` every pill keeps its name visible.
private struct TabPill: View {
    let item: DashboardTab
    let isSelected: Bool
    var alwaysLabel = false
    let action: () -> Void
    @State private var hovering = false

    private var showsLabel: Bool { alwaysLabel || isSelected }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                if showsLabel {
                    Text(item.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, showsLabel ? 12 : 9)
            .padding(.vertical, 7)
            .background(background, in: Capsule())
            .foregroundStyle(isSelected ? .white : hovering ? Color.primary : Color.secondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(item.title)
        .onHover { hovering = $0 }
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Theme.accent.opacity(0.30)) }
        if hovering { return AnyShapeStyle(Color.white.opacity(0.08)) }
        return AnyShapeStyle(Color.clear)
    }
}

/// Battery text lives in its own view so SystemStats updates only
/// re-render this label, not the whole dashboard.
private struct BatteryBadge: View {
    @EnvironmentObject private var stats: SystemStats

    var body: some View {
        if let battery = stats.battery {
            Label(battery, systemImage: "battery.75percent")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
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
