import ServiceManagement
import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tracker: TimeTracker
    @EnvironmentObject private var clipboard: ClipboardStore
    @EnvironmentObject private var links: LinkStore
    @EnvironmentObject private var home: HomeStore
    @EnvironmentObject private var location: LocationStore
    @EnvironmentObject private var tabPrefs: TabPrefs

    @AppStorage("hotkeyPreset") private var hotkeyIndex = 0
    @State private var loginError: String?
    @State private var newSubject = ""
    @State private var newLinkTitle = ""
    @State private var newLinkURL = ""
    @State private var citySearch = ""
    @AppStorage("discordWebhook") private var discordWebhook = ""

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    appearanceCard
                    generalCard
                    locationCard
                    aboutCard
                }
                VStack(spacing: 14) {
                    tabsCard
                    integrationsCard
                    subjectsCard
                    linksCard
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        Card(title: "Appearance", systemImage: "paintbrush") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Accent color")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(AccentChoice.allCases) { choice in
                        Button {
                            settings.accent = choice
                        } label: {
                            Circle()
                                .fill(choice.color)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(
                                    .white.opacity(settings.accent == choice ? 0.9 : 0),
                                    lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .help(choice.name)
                    }
                }
                Text("Background")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                HStack(spacing: 8) {
                    ForEach(BackgroundChoice.allCases) { choice in
                        Button {
                            settings.background = choice
                        } label: {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(choice.gradient)
                                .frame(width: 44, height: 26)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                                    settings.background == choice ? .white.opacity(0.9) : Theme.cardStroke,
                                    lineWidth: settings.background == choice ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .help(choice.name)
                    }
                }
                Divider()
                Toggle("Show tab names in the tab bar", isOn: $settings.tabLabels)
                    .toggleStyle(.switch)
                Toggle("Show seconds on the clock", isOn: $settings.showSeconds)
                    .toggleStyle(.switch)
                Toggle("Show battery in the header", isOn: $settings.showBattery)
                    .toggleStyle(.switch)
                Divider()
                Picker("Open on tab", selection: $settings.defaultTab) {
                    ForEach(DashboardTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                Text("Which tab the dashboard shows when the app starts.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 12))
        }
    }

    // MARK: - Location

    private var locationCard: some View {
        Card(title: "Location", systemImage: "location") {
            VStack(alignment: .leading, spacing: 8) {
                if let name = location.name {
                    Label(name, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Text("No location set — weather, sun, map and earthquake alerts need one.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Search city (e.g. New Delhi)…", text: $citySearch)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit { location.search(citySearch) }
                    Button("Search") { location.search(citySearch) }
                        .controlSize(.small)
                }
                ForEach(location.searchResults) { result in
                    Button {
                        location.set(result)
                        citySearch = ""
                    } label: {
                        HStack {
                            Text(result.display).font(.system(size: 11))
                            Spacer()
                            Image(systemName: "checkmark.circle").font(.system(size: 10))
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                Text("Stored only on this Mac; used for the Weather, Map and Clocks tabs.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Tabs

    private var tabsCard: some View {
        Card(title: "Tabs", systemImage: "rectangle.topthird.inset.filled") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose which tabs appear. Home and Settings always stay.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                ForEach(tabPrefs.orderedTabs.filter { $0 != .home && $0 != .settings }) { tab in
                    HStack(spacing: 6) {
                        Toggle(isOn: Binding(get: { tabPrefs.isVisible(tab) },
                                             set: { _ in tabPrefs.toggle(tab) })) {
                            Label(tab.title, systemImage: tab.icon)
                                .font(.system(size: 12))
                        }
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        Spacer()
                        Button { tabPrefs.move(tab, by: -1) } label: {
                            Image(systemName: "arrow.up").font(.system(size: 9))
                        }
                        Button { tabPrefs.move(tab, by: 1) } label: {
                            Image(systemName: "arrow.down").font(.system(size: 9))
                        }
                    }
                    .buttonStyle(.borderless)
                }
                Text("Hidden tabs stay reachable from the ⋯ menu and the palette.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - General

    private var generalCard: some View {
        Card(title: "General", systemImage: "gearshape") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)
                if let loginError {
                    Text("Couldn't change login item: \(loginError)")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
                Divider()
                Picker("Palette hotkey", selection: $hotkeyIndex) {
                    ForEach(Array(HotKeyPreset.all.enumerated()), id: \.offset) { index, preset in
                        Text(preset.name).tag(index)
                    }
                }
                .onChange(of: hotkeyIndex) {
                    NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                }
                Toggle("⇧⌘S takes a snip (global)", isOn: $settings.snipHotkey)
                    .toggleStyle(.switch)
                    .onChange(of: settings.snipHotkey) {
                        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                    }
                Text("Changes apply immediately, everywhere on your Mac. Turn the snip shortcut off if another app needs ⇧⌘S.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Divider()
                Toggle("Capture clipboard history", isOn: $clipboard.capturing)
                    .toggleStyle(.switch)
                Picker("Clipboard history size", selection: $settings.clipboardLimit) {
                    ForEach([20, 50, 100, 200], id: \.self) { size in
                        Text("\(size) items").tag(size)
                    }
                }
                Divider()
                Stepper("Daily study goal: \(formatHM(tracker.dailyGoalMinutes * 60))",
                        value: Binding(get: { tracker.dailyGoalMinutes },
                                       set: { tracker.setGoal($0) }),
                        in: 15...720, step: 15)
                Picker("Auto-stop tracking when idle", selection: $settings.idleAutoStopMinutes) {
                    Text("Off").tag(0)
                    ForEach([3, 5, 10, 15], id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                Text("Walking away pauses the study stopwatch so idle time never counts.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 12))
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enable in
                do {
                    if enable {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    loginError = nil
                } catch {
                    loginError = error.localizedDescription
                }
            }
        )
    }

    // MARK: - Integrations

    private var integrationsCard: some View {
        Card(title: "Integrations", systemImage: "puzzlepiece.extension") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Discord webhook")
                    .font(.system(size: 11, weight: .semibold))
                TextField("https://discord.com/api/webhooks/…", text: $discordWebhook)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                HStack {
                    Button("Send Test Message") {
                        Discord.send("✅ Command Central is connected!")
                    }
                    .controlSize(.small)
                    .disabled(discordWebhook.isEmpty)
                    Spacer()
                }
                Text("In Discord: Server Settings → Integrations → Webhooks → New Webhook → Copy URL. Then use “discord <message>” in the ⌥Space palette, or “Send Daily Summary to Discord”.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Subjects

    private var subjectsCard: some View {
        Card(title: "Study Subjects", systemImage: "books.vertical",
             trailing: "\(tracker.subjects.count)") {
            VStack(spacing: 6) {
                ForEach(tracker.subjects, id: \.self) { subject in
                    HStack {
                        Text(subject).font(.system(size: 12))
                        Spacer()
                        Text(formatHM(allTime(subject)))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button { tracker.removeSubject(subject) } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 7))
                }
                HStack {
                    TextField("New subject…", text: $newSubject)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit(addSubject)
                    Button(action: addSubject) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(newSubject.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func allTime(_ subject: String) -> Int {
        tracker.bySubject(.all).first { $0.subject == subject }?.seconds ?? 0
    }

    private func addSubject() {
        let name = newSubject.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        tracker.addSubjectIfNeeded(name)
        newSubject = ""
    }

    // MARK: - Quick links

    private var linksCard: some View {
        Card(title: "Quick Links", systemImage: "link",
             trailing: "\(links.links.count)") {
            VStack(spacing: 6) {
                ForEach(links.links) { link in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(link.title).font(.system(size: 12))
                            Text(link.url)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button { links.remove(link.id) } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 7))
                }
                HStack {
                    TextField("Title", text: $newLinkTitle)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 110)
                    TextField("URL or file path", text: $newLinkURL)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit(addLink)
                    Button(action: addLink) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(newLinkTitle.isEmpty || newLinkURL.isEmpty)
                }
                Text("Links show in the Quick Links widget and the ⌥Space palette.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func addLink() {
        links.add(title: newLinkTitle, url: newLinkURL)
        newLinkTitle = ""
        newLinkURL = ""
    }

    // MARK: - About

    private var aboutCard: some View {
        Card(title: "About", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Command Central \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .font(.system(size: 12, weight: .medium))
                Text("Everything is stored locally in JSON files — no accounts, no cloud.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Data Folder") {
                        NSWorkspace.shared.open(Storage.directory)
                    }
                    Button("Reset Home Layout") {
                        home.resetLayout()
                    }
                }
                .controlSize(.small)
            }
        }
    }
}
