import AppKit
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var home: HomeStore
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if editing {
                    Text("Customizing — reorder, resize or remove widgets")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if editing {
                    if !home.available.isEmpty {
                        Menu {
                            ForEach(home.available) { kind in
                                Button {
                                    home.add(kind)
                                } label: {
                                    Label(kind.title, systemImage: kind.icon)
                                }
                            }
                        } label: {
                            Label("Add Widget", systemImage: "plus")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    Button("Reset Layout") { home.resetLayout() }
                    Button("Done") { editing = false }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button {
                        editing = true
                    } label: {
                        Label("Customize", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .controlSize(.small)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
                                         count: 3),
                          alignment: .leading, spacing: 14) {
                    ForEach(home.widgets) { config in
                        WidgetContainer(config: config, editing: $editing)
                    }
                }
                if home.widgets.isEmpty {
                    Text("No widgets — click Customize → Add Widget")
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                }
            }
        }
    }
}

struct WidgetContainer: View {
    let config: WidgetConfig
    @Binding var editing: Bool
    @EnvironmentObject private var home: HomeStore

    private var height: CGFloat {
        config.expanded ? 370 : 230
    }

    var body: some View {
        widgetContent
            .frame(height: height, alignment: .top)
            .allowsHitTesting(!editing)
            .overlay(alignment: .topTrailing) {
                if editing { controls }
            }
    }

    @ViewBuilder
    private var widgetContent: some View {
        switch config.kind {
        case .clock: ClockWidget()
        case .tasks: TasksCard()
        case .timer: TimerCard()
        case .media: MediaCard()
        case .calendar: CalendarCard(cellSize: config.expanded ? 32 : 24)
        case .system: ProcessesCard()
        case .links: LinksWidget()
        case .notes: NotesWidget()
        case .clipboard: ClipboardWidget()
        case .hours: HoursWidget()
        case .streak: StreakWidget()
        case .weather: WeatherWidget()
        case .sun: SunWidgetSmall()
        case .worldclock: WorldClockWidget()
        case .sleepw: SleepWidget()
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { home.move(config.kind, by: -1) } label: {
                Image(systemName: "arrow.left")
            }
            Button { home.move(config.kind, by: 1) } label: {
                Image(systemName: "arrow.right")
            }
            Button { home.toggleSize(config.kind) } label: {
                Image(systemName: config.expanded
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
            }
            Button { home.remove(config.kind) } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.red)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thickMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 1))
        .padding(8)
    }
}

// MARK: - Home-only widgets

struct ClockWidget: View {
    var body: some View {
        Card(title: "Clock", systemImage: "clock") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 6) {
                    Text(context.date, format: .dateTime.hour().minute().second())
                        .font(.system(size: 44, weight: .light).monospacedDigit())
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Week \(Calendar.current.component(.weekOfYear, from: context.date))")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

struct LinksWidget: View {
    @EnvironmentObject private var links: LinkStore

    var body: some View {
        Card(title: "Quick Links", systemImage: "link") {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(links.links) { link in
                        Button {
                            if let url = URL(string: link.url) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: link.url.hasPrefix("file:") ? "folder" : "globe")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text(link.title)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.forward")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}

struct NotesWidget: View {
    @EnvironmentObject private var notes: NoteStore
    @EnvironmentObject private var state: AppState
    @State private var quickNote = ""

    var body: some View {
        Card(title: "Notes", systemImage: "note.text",
             trailing: "\(notes.notes.count)") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Jot something…", text: $quickNote)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let text = quickNote.trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { return }
                        notes.add(text: text)
                        quickNote = ""
                    }
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(notes.notes.prefix(5)) { note in
                            Button {
                                state.showDashboardTab(.notes)
                            } label: {
                                HStack {
                                    Text(note.title)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(note.updatedAt, format: .dateTime.day().month())
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 8)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}

struct HoursWidget: View {
    @EnvironmentObject private var tracker: TimeTracker
    @EnvironmentObject private var state: AppState

    var body: some View {
        Card(title: "Study Hours", systemImage: "hourglass") {
            VStack(spacing: 10) {
                Text(formatHM(tracker.todaySeconds))
                    .font(.system(size: 34, weight: .light).monospacedDigit())
                ProgressView(value: min(1, Double(tracker.todaySeconds) / Double(tracker.dailyGoalMinutes * 60)))
                    .tint(Theme.accent)
                Text("Goal: \(formatHM(tracker.dailyGoalMinutes * 60)) · Week: \(formatHM(tracker.seconds(in: .week)))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if let top = tracker.bySubjectToday().first {
                    Text("Most today: \(top.subject) (\(formatHM(top.seconds)))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Button("Open Tracker") { state.showDashboardTab(.tracker) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}

struct StreakWidget: View {
    @EnvironmentObject private var tracker: TimeTracker

    var body: some View {
        Card(title: "Streak", systemImage: "flame") {
            VStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.flame)
                Text("\(tracker.currentStreak) day\(tracker.currentStreak == 1 ? "" : "s")")
                    .font(.system(size: 26, weight: .semibold))
                Text("Best: \(tracker.bestStreak) · Month: \(formatHM(tracker.seconds(in: .month)))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("\(tracker.activeDaysThisMonth) active days this month")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }
}

struct WeatherWidget: View {
    @EnvironmentObject private var weather: WeatherStore
    @EnvironmentObject private var location: LocationStore
    @EnvironmentObject private var state: AppState

    var body: some View {
        Card(title: "Weather", systemImage: "cloud.sun") {
            if location.isSet {
                VStack(spacing: 6) {
                    Text(weather.emoji).font(.system(size: 34))
                    Text(weather.temperature.map { "\(Int($0.rounded()))°C" } ?? "—")
                        .font(.system(size: 28, weight: .light))
                    Text(weather.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let alert = weather.alerts.first {
                        Text(alert)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.flame)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    Text(location.name ?? "")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    Text("Set a location to see weather")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("Settings") { state.showDashboardTab(.settings) }
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

struct SunWidgetSmall: View {
    @EnvironmentObject private var weather: WeatherStore

    var body: some View {
        Card(title: "Sun", systemImage: "sunrise") {
            VStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    SunArc(sunrise: weather.sunrise, sunset: weather.sunset, now: context.date)
                        .frame(height: 70)
                }
                HStack {
                    Label(weather.sunrise.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—",
                          systemImage: "sunrise.fill")
                    Spacer()
                    Label(weather.sunset.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—",
                          systemImage: "sunset.fill")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

struct WorldClockWidget: View {
    @EnvironmentObject private var clocks: WorldClockStore

    var body: some View {
        Card(title: "World Clocks", systemImage: "globe") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 4) {
                    ForEach(clocks.zones.prefix(4), id: \.self) { zone in
                        HStack {
                            Text(WorldClockStore.cityName(zone))
                                .font(.system(size: 12))
                            Spacer()
                            Text(context.date, format: Self.style(for: zone))
                                .font(.system(size: 13, weight: .light).monospacedDigit())
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    static func style(for zone: String) -> Date.FormatStyle {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(identifier: zone) ?? .current
        return style
    }
}

struct SleepWidget: View {
    @EnvironmentObject private var sleep: SleepMonitor

    var body: some View {
        Card(title: "Sleep", systemImage: "bed.double") {
            VStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)
                Text(sleep.nightSeconds().map { formatHM($0) } ?? "—")
                    .font(.system(size: 26, weight: .light))
                Text("last night (Mac downtime)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: .infinity)
    }
}

struct ClipboardWidget: View {
    @EnvironmentObject private var clipboard: ClipboardStore

    var body: some View {
        Card(title: "Clipboard", systemImage: "doc.on.clipboard",
             trailing: "\(clipboard.items.count)") {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(clipboard.items.prefix(6)) { item in
                        Button {
                            clipboard.copy(item)
                        } label: {
                            HStack {
                                Text(item.text.replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .help("Copy again")
                    }
                    if clipboard.items.isEmpty {
                        Text("Copy something and it appears here")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}
