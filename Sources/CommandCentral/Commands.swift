import AppKit
import Foundation
import JavaScriptCore

struct Command: Identifiable {
    enum Icon {
        case symbol(String)
        case file(String)
    }

    let id: String
    let title: String
    var subtitle: String? = nil
    var icon: Icon = .symbol("terminal")
    /// When true the palette stays open after running (e.g. toggling a task).
    var keepOpen = false
    let action: () -> Void
}

final class CommandEngine {
    private unowned let state: AppState

    init(state: AppState) {
        self.state = state
    }

    func results(for rawQuery: String) -> [Command] {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)

        if query.isEmpty { return defaultResults() }

        // Secret: typing exactly "journal" reveals the hidden diary.
        if query.lowercased() == "journal" {
            return [journalCommand()]
        }

        // "ss" → Snip & Sketch, Windows-style.
        if query.lowercased() == "ss" {
            return SnipStore.Mode.allCases.map { snipCommand($0) }
        }

        var results: [Command] = []

        // "task buy milk" / "todo buy milk" → add a task
        for prefix in ["task ", "todo ", "add "] where query.lowercased().hasPrefix(prefix) {
            let title = String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty {
                results.append(addTaskCommand(title: title))
            }
            break
        }

        // "note remember this" → save a quick note
        if query.lowercased().hasPrefix("note ") {
            let text = String(query.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                results.append(addNoteCommand(text: text))
            }
        }

        // "track maths" → start the study stopwatch
        if query.lowercased().hasPrefix("track ") {
            let subject = String(query.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if !subject.isEmpty {
                results.append(trackCommand(subject: subject))
            }
        }

        // "discord hello team" → post to your Discord webhook
        if query.lowercased().hasPrefix("discord ") {
            let message = String(query.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            if !message.isEmpty {
                results.append(discordMessageCommand(message))
            }
        }

        // "claude how do I …" → Claude Code in the Terminal tab
        if query.lowercased().hasPrefix("claude ") {
            let prompt = String(query.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            if !prompt.isEmpty {
                results.append(claudeCommand(prompt: prompt))
            }
        }

        // "alarm 7:30 wake up" → set an alarm
        if let alarm = parseAlarmQuery(query) {
            results.append(alarm)
        }

        // "g swift arrays" / "yt lofi" / "wiki fourier" → web searches
        for (prefix, name, base) in [("g ", "Google", "https://www.google.com/search?q="),
                                     ("yt ", "YouTube", "https://www.youtube.com/results?search_query="),
                                     ("wiki ", "Wikipedia", "https://en.wikipedia.org/wiki/Special:Search?search=")]
        where query.lowercased().hasPrefix(prefix) {
            let term = String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !term.isEmpty {
                results.append(searchCommand(engine: name, base: base, term: term))
            }
        }

        // "example.com" → open it
        if query.range(of: #"^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+(/\S*)?$"#,
                       options: .regularExpression) != nil {
            results.append(openURLCommand(query))
        }

        // "12*45+8" → calculator
        if let calc = calculatorCommand(for: query) {
            results.insert(calc, at: 0)
        }

        // "focus 15" / "timer 15" → custom-length focus session
        if let minutes = parseTimerQuery(query) {
            results.append(startTimerCommand(minutes: minutes))
        }

        results += rankedMatches(for: query)
        return Array(results.prefix(15))
    }

    // MARK: - Ranking

    private func rankedMatches(for query: String) -> [Command] {
        var scored: [(Int, Command)] = []

        func consider(_ target: String, _ command: Command) {
            if let s = Fuzzy.score(query: query, target: target) {
                scored.append((s, command))
            }
        }

        for task in state.tasks.openTasks {
            consider(task.title, toggleTaskCommand(task))
            consider("track " + task.title, trackTaskCommand(task))
        }
        if state.timer.isRunning {
            consider("stop focus timer", stopTimerCommand())
        } else {
            consider("start focus timer pomodoro", startTimerCommand(minutes: 25))
        }
        if state.tracker.isTracking {
            consider("stop tracking study", stopTrackingCommand())
        }
        for link in state.links.links {
            consider(link.title, openLinkCommand(link))
        }
        for app in state.apps.apps {
            consider(app.name, openAppCommand(app))
        }
        consider("open dashboard", dashboardCommand())
        for tab in DashboardTab.allCases where tab != .home {
            consider("open \(tab.title.lowercased()) tab", tabCommand(tab))
        }
        consider("chrome", browserCommand(id: "chrome-new",
                                          title: "New Chrome Window",
                                          subtitle: "Opens google.com — add “inc” for incognito",
                                          app: "Google Chrome",
                                          args: ["--new-window"]))
        consider("chrome inc incognito", browserCommand(id: "chrome-inc",
                                                        title: "New Chrome Incognito Window",
                                                        subtitle: "Private browsing on google.com",
                                                        app: "Google Chrome",
                                                        args: ["--incognito"]))
        consider("brave", browserCommand(id: "brave-new",
                                         title: "New Brave Window",
                                         subtitle: "Opens google.com — add “inc” for private",
                                         app: "Brave Browser",
                                         args: ["--new-window"]))
        consider("brave inc incognito private", browserCommand(id: "brave-inc",
                                                               title: "New Brave Private Window",
                                                               subtitle: "Private browsing on google.com",
                                                               app: "Brave Browser",
                                                               args: ["--incognito"]))
        consider("discord daily summary send", discordSummaryCommand())

        // System actions
        consider("lock screen", shellCommand(id: "lock", title: "Lock Screen",
                                             subtitle: "Puts displays to sleep",
                                             icon: "lock.display",
                                             exec: "/usr/bin/pmset", args: ["displaysleepnow"]))
        consider("sleep mac", shellCommand(id: "sleep-mac", title: "Sleep Mac",
                                           subtitle: "Full system sleep",
                                           icon: "moon.fill",
                                           exec: "/usr/bin/pmset", args: ["sleepnow"]))
        for mode in SnipStore.Mode.allCases {
            consider("ss snip screenshot sketch capture \(mode.title.lowercased())", snipCommand(mode))
        }
        consider("empty trash", scriptCommand(id: "trash", title: "Empty Trash",
                                              subtitle: "Asks Finder to empty the Trash",
                                              icon: "trash",
                                              source: "tell application \"Finder\" to empty trash"))
        consider("toggle dark light mode appearance", scriptCommand(id: "darkmode", title: "Toggle Dark Mode",
                                                                    subtitle: "System-wide appearance",
                                                                    icon: "circle.lefthalf.filled",
                                                                    source: "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"))
        consider("copy ip address network", copyIPCommand())
        consider("wifi on", shellCommand(id: "wifi-on", title: "Turn Wi-Fi On",
                                         icon: "wifi",
                                         exec: "/usr/sbin/networksetup", args: ["-setairportpower", "en0", "on"]))
        consider("wifi off", shellCommand(id: "wifi-off", title: "Turn Wi-Fi Off",
                                          icon: "wifi.slash",
                                          exec: "/usr/sbin/networksetup", args: ["-setairportpower", "en0", "off"]))
        consider("downloads folder", folderCommand(id: "dl", title: "Open Downloads", path: "~/Downloads"))
        consider("desktop folder", folderCommand(id: "desk", title: "Open Desktop", path: "~/Desktop"))
        consider("documents folder", folderCommand(id: "docs", title: "Open Documents", path: "~/Documents"))
        consider("system settings preferences", shellCommand(id: "sysset", title: "Open System Settings",
                                                             icon: "gearshape.2",
                                                             exec: "/usr/bin/open", args: ["-a", "System Settings"]))
        consider("activity monitor", shellCommand(id: "actmon", title: "Open Activity Monitor",
                                                  icon: "waveform.path.ecg",
                                                  exec: "/usr/bin/open", args: ["-a", "Activity Monitor"]))
        consider("refresh weather quakes", Command(id: "refresh-weather", title: "Refresh Weather & Quakes",
                                                   icon: .symbol("arrow.clockwise")) { [state] in
            state.weather.refresh()
            state.quakes.refresh()
        })
        consider("clear clipboard history", Command(id: "clear-clips", title: "Clear Clipboard History",
                                                    icon: .symbol("doc.on.clipboard"),
                                                    keepOpen: true) { [state] in
            state.clipboard.clear()
        })
        consider("claude code terminal ai", claudeCommand(prompt: nil))

        // Your custom commands
        for custom in state.custom.commands {
            consider(custom.keywords + " " + custom.title, Command(
                id: "custom-\(custom.id.uuidString)",
                title: custom.title,
                subtitle: "Custom — \(custom.kind.label)",
                icon: .symbol(custom.kind.icon)) {
                custom.run()
            })
        }

        consider("all tasks", allTasksHintCommand())
        consider("clear completed tasks", clearCompletedCommand())
        consider("edit quick links", editLinksCommand())
        consider("quit command central", quitCommand())

        for note in state.notes.notes.prefix(50) {
            consider(note.title, Command(id: "note-\(note.id.uuidString)",
                                         title: note.title,
                                         subtitle: "Note — opens the Notes tab",
                                         icon: .symbol("note.text")) { [state] in
                state.showDashboardTab(.notes)
            })
        }
        for item in state.clipboard.items.prefix(30) {
            let flat = item.text.replacingOccurrences(of: "\n", with: " ")
            consider(flat, Command(id: "clip-\(item.id.uuidString)",
                                   title: String(flat.prefix(60)),
                                   subtitle: "Clipboard history — ⏎ copies it again",
                                   icon: .symbol("doc.on.doc")) { [state] in
                state.clipboard.copy(item)
            })
        }

        return scored.sorted { $0.0 > $1.0 }.map(\.1)
    }

    private func defaultResults() -> [Command] {
        var results: [Command] = [dashboardCommand()]
        results += state.tasks.openTasks.prefix(4).map(toggleTaskCommand)
        results.append(state.timer.isRunning ? stopTimerCommand()
                                             : startTimerCommand(minutes: 25))
        results += state.links.links.map(openLinkCommand)
        return results
    }

    private func parseTimerQuery(_ query: String) -> Int? {
        let parts = query.lowercased().split(separator: " ")
        guard parts.count == 2,
              ["focus", "timer", "pomodoro"].contains(String(parts[0])),
              let minutes = Int(parts[1]), (1...720).contains(minutes) else { return nil }
        return minutes
    }

    // MARK: - Command builders

    private func addTaskCommand(title: String) -> Command {
        Command(id: "add-task",
                title: "Add Task: \(title)",
                subtitle: "Saved to your local task list",
                icon: .symbol("plus.circle"),
                keepOpen: false) { [state] in
            state.tasks.add(title)
        }
    }

    private func toggleTaskCommand(_ task: TaskItem) -> Command {
        Command(id: "task-\(task.id.uuidString)",
                title: task.title,
                subtitle: "Task — press ⏎ to mark done",
                icon: .symbol("circle"),
                keepOpen: true) { [state] in
            state.tasks.toggle(task.id)
        }
    }

    private func allTasksHintCommand() -> Command {
        let open = state.tasks.openTasks.count
        return Command(id: "all-tasks",
                       title: "Tasks: \(open) open",
                       subtitle: "Type “task <text>” to add a new one",
                       icon: .symbol("checklist"),
                       keepOpen: true) {}
    }

    private func clearCompletedCommand() -> Command {
        Command(id: "clear-completed",
                title: "Clear Completed Tasks",
                icon: .symbol("checkmark.circle.badge.xmark"),
                keepOpen: true) { [state] in
            state.tasks.clearCompleted()
        }
    }

    private func startTimerCommand(minutes: Int) -> Command {
        Command(id: "start-timer-\(minutes)",
                title: "Start Focus Timer (\(minutes) min)",
                subtitle: "Countdown shows in the menu bar — “focus 15” for a custom length",
                icon: .symbol("timer")) { [state] in
            state.timer.start(minutes: minutes, subject: state.tracker.subjects.first)
        }
    }

    private func trackCommand(subject: String) -> Command {
        Command(id: "track",
                title: "Start Tracking: \(subject)",
                subtitle: "Stopwatch — hours are logged to this subject",
                icon: .symbol("record.circle")) { [state] in
            state.tracker.startStopwatch(subject)
        }
    }

    private func trackTaskCommand(_ task: TaskItem) -> Command {
        Command(id: "track-task-\(task.id.uuidString)",
                title: "Track: \(task.title)",
                subtitle: "Stopwatch on this task — logs to \(task.subject ?? state.tracker.subjects.first ?? "Other")",
                icon: .symbol("record.circle")) { [state] in
            state.tracker.startStopwatch(task.subject ?? state.tracker.subjects.first ?? "Other",
                                         detail: task.title,
                                         taskId: task.id)
        }
    }

    private func stopTrackingCommand() -> Command {
        Command(id: "stop-tracking",
                title: "Stop Tracking \(state.tracker.activeSubject ?? "")",
                subtitle: "\(formatHMS(state.tracker.activeSeconds)) elapsed — saves to your hours",
                icon: .symbol("stop.circle")) { [state] in
            state.tracker.stopStopwatch()
        }
    }

    private func stopTimerCommand() -> Command {
        Command(id: "stop-timer",
                title: "Stop Focus Timer",
                subtitle: "\(state.timer.remainingText) remaining",
                icon: .symbol("stop.circle")) { [state] in
            state.timer.stop()
        }
    }

    private func openLinkCommand(_ link: QuickLink) -> Command {
        Command(id: "link-\(link.id)",
                title: link.title,
                subtitle: link.url,
                icon: .symbol(link.url.hasPrefix("file:") ? "folder" : "globe")) {
            if let url = URL(string: link.url) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func editLinksCommand() -> Command {
        Command(id: "edit-links",
                title: "Edit Quick Links",
                subtitle: "Opens links.json — changes load on next launch",
                icon: .symbol("link.badge.plus")) { [state] in
            NSWorkspace.shared.open(state.links.fileURL)
        }
    }

    private func openAppCommand(_ app: AppEntry) -> Command {
        Command(id: "app-\(app.path)",
                title: app.name,
                subtitle: "Application",
                icon: .file(app.path)) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path),
                                               configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func dashboardCommand() -> Command {
        Command(id: "dashboard",
                title: "Open Dashboard",
                subtitle: "Your customizable home with widgets",
                icon: .symbol("rectangle.grid.2x2")) { [state] in
            state.showDashboardTab(.home)
        }
    }

    private func tabCommand(_ tab: DashboardTab) -> Command {
        Command(id: "tab-\(tab.rawValue)",
                title: "Open \(tab.title)",
                subtitle: "Dashboard tab",
                icon: .symbol(tab.icon)) { [state] in
            state.showDashboardTab(tab)
        }
    }

    private func addNoteCommand(text: String) -> Command {
        Command(id: "add-note",
                title: "Save Note: \(text)",
                subtitle: "Added to your Notes tab",
                icon: .symbol("note.text.badge.plus")) { [state] in
            state.notes.add(text: text)
        }
    }

    private func snipCommand(_ mode: SnipStore.Mode) -> Command {
        Command(id: "snip-\(mode.rawValue)",
                title: "Snip: \(mode.title)",
                subtitle: mode.subtitle + " — saved to Snips & copied",
                icon: .symbol(mode.icon)) { [state] in
            state.startSnip(mode)
        }
    }

    private func journalCommand() -> Command {
        Command(id: "journal",
                title: "Open Journal",
                subtitle: "Password-protected diary",
                icon: .symbol("lock.shield")) { [state] in
            state.showJournal()
        }
    }

    private func browserCommand(id: String, title: String, subtitle: String,
                                app: String, args: [String]) -> Command {
        Command(id: id,
                title: title,
                subtitle: subtitle,
                icon: .symbol(args.contains("--incognito") ? "eyeglasses" : "globe")) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-na", app, "--args"] + args + ["https://www.google.com"]
            try? process.run()
        }
    }

    private func discordMessageCommand(_ message: String) -> Command {
        Command(id: "discord-msg",
                title: "Discord: \(message)",
                subtitle: Discord.isConfigured ? "Send to your webhook channel"
                                               : "Set a webhook URL in Settings first",
                icon: .symbol("paperplane")) {
            Discord.send(message)
        }
    }

    private func discordSummaryCommand() -> Command {
        Command(id: "discord-summary",
                title: "Send Daily Summary to Discord",
                subtitle: Discord.isConfigured ? "Hours, tasks & streak to your webhook"
                                               : "Set a webhook URL in Settings first",
                icon: .symbol("chart.bar.doc.horizontal")) { [state] in
            let studied = formatHM(state.tracker.todaySeconds)
            let top = state.tracker.bySubjectToday().first
                .map { " (top: \($0.subject) \(formatHM($0.seconds)))" } ?? ""
            let doneCount = state.tasks.items.filter {
                guard let doneAt = $0.doneAt else { return false }
                return Calendar.current.isDateInToday(doneAt)
            }.count
            Discord.send("📊 **Daily Summary** — Studied: \(studied)\(top) · Tasks done: \(doneCount) · Streak: \(state.tracker.currentStreak)🔥")
        }
    }

    private func quitCommand() -> Command {
        Command(id: "quit",
                title: "Quit Command Central",
                icon: .symbol("power")) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - New command builders

    private func shellCommand(id: String, title: String, subtitle: String? = nil,
                              icon: String, exec: String, args: [String]) -> Command {
        Command(id: id, title: title, subtitle: subtitle, icon: .symbol(icon)) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: exec)
            process.arguments = args
            try? process.run()
        }
    }

    private func scriptCommand(id: String, title: String, subtitle: String? = nil,
                               icon: String, source: String) -> Command {
        Command(id: id, title: title, subtitle: subtitle, icon: .symbol(icon)) {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }

    private func folderCommand(id: String, title: String, path: String) -> Command {
        Command(id: id, title: title, subtitle: path, icon: .symbol("folder")) {
            NSWorkspace.shared.open(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        }
    }

    private func copyIPCommand() -> Command {
        Command(id: "copy-ip",
                title: "Copy IP Address",
                subtitle: "Local network address → clipboard",
                icon: .symbol("network")) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
            process.arguments = ["getifaddr", "en0"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()
            let ip = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !ip.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ip, forType: .string)
                NotificationManager.shared.notify(title: "IP copied", body: ip)
            }
        }
    }

    private func claudeCommand(prompt: String?) -> Command {
        Command(id: "claude",
                title: prompt.map { "Ask Claude Code: \($0)" } ?? "Open Claude Code Terminal",
                subtitle: "Runs in the Terminal tab",
                icon: .symbol("sparkles")) { [state] in
            state.showDashboardTab(.terminal)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let prompt {
                    let escaped = prompt.replacingOccurrences(of: "\"", with: "\\\"")
                    TerminalSession.shared.sendCommand("claude \"\(escaped)\"")
                } else {
                    TerminalSession.shared.sendCommand("claude")
                }
            }
        }
    }

    private func parseAlarmQuery(_ query: String) -> Command? {
        let lower = query.lowercased()
        guard lower.hasPrefix("alarm ") else { return nil }
        let rest = String(query.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        let parts = rest.split(separator: " ", maxSplits: 1)
        guard let timePart = parts.first else { return nil }
        let timePieces = timePart.split(separator: ":")
        guard timePieces.count == 2,
              let hour = Int(timePieces[0]), (0...23).contains(hour),
              let minute = Int(timePieces[1]), (0...59).contains(minute) else { return nil }
        let label = parts.count > 1 ? String(parts[1]) : "Alarm"
        return Command(id: "set-alarm",
                       title: String(format: "Set Alarm %02d:%02d — %@", hour, minute, label),
                       subtitle: "Rings while the app is running",
                       icon: .symbol("alarm")) { [state] in
            state.alarms.add(hour: hour, minute: minute, label: label)
        }
    }

    private func searchCommand(engine: String, base: String, term: String) -> Command {
        Command(id: "search-\(engine)",
                title: "Search \(engine): \(term)",
                icon: .symbol("magnifyingglass")) {
            let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
            if let url = URL(string: base + encoded) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func openURLCommand(_ text: String) -> Command {
        Command(id: "open-url",
                title: "Open \(text)",
                subtitle: "In your default browser",
                icon: .symbol("safari")) {
            if let url = URL(string: "https://" + text) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func calculatorCommand(for query: String) -> Command? {
        guard query.range(of: #"^[0-9+\-*/(). %^]+$"#, options: .regularExpression) != nil,
              query.rangeOfCharacter(from: .decimalDigits) != nil,
              query.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/%^")) != nil,
              let context = JSContext() else { return nil }
        let expression = query.replacingOccurrences(of: "^", with: "**")
        guard let value = context.evaluateScript(expression)?.toNumber()?.doubleValue,
              value.isFinite else { return nil }
        let text = value == value.rounded() && abs(value) < 1e15
            ? String(Int(value))
            : String(format: "%g", value)
        return Command(id: "calc",
                       title: "= \(text)",
                       subtitle: "\(query) — press ⏎ to copy the result",
                       icon: .symbol("plus.forwardslash.minus"),
                       keepOpen: true) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
