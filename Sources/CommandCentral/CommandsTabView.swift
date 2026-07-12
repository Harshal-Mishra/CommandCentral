import SwiftUI

private struct RefEntry: Identifiable {
    let syntax: String
    let detail: String
    var id: String { syntax }
}

private let typeAheadRefs: [RefEntry] = [
    RefEntry(syntax: "task buy notebook", detail: "Add a task to your list"),
    RefEntry(syntax: "note remember this", detail: "Save a quick note"),
    RefEntry(syntax: "focus 45  ·  timer 90", detail: "Start a focus timer (minutes, up to 720)"),
    RefEntry(syntax: "track maths", detail: "Start the study stopwatch on a subject"),
    RefEntry(syntax: "track <task name>", detail: "Stopwatch pinned to a task — same as ▶ on the task"),
    RefEntry(syntax: "alarm 7:30 wake up", detail: "Set an alarm with a label"),
    RefEntry(syntax: "discord hello team", detail: "Post a message to your Discord webhook"),
    RefEntry(syntax: "claude explain closures", detail: "Ask Claude Code in the Terminal tab"),
    RefEntry(syntax: "g swift arrays", detail: "Google search"),
    RefEntry(syntax: "yt lofi beats", detail: "YouTube search"),
    RefEntry(syntax: "wiki fourier transform", detail: "Wikipedia search"),
    RefEntry(syntax: "ss", detail: "Snip & Sketch — area/window/screen shot, auto-copied, saved to Snips"),
    RefEntry(syntax: "12*45+8", detail: "Inline calculator — ⏎ copies the result"),
    RefEntry(syntax: "github.com/harshal", detail: "Any web address opens directly"),
    RefEntry(syntax: "chrome  ·  chrome inc", detail: "New Chrome window / incognito, on google.com"),
    RefEntry(syntax: "brave  ·  brave inc", detail: "New Brave window / private, on google.com"),
]

private let actionRefs: [RefEntry] = [
    RefEntry(syntax: "open <tab name>", detail: "Jump to any tab — Tracker, Weather, Map, Notes…"),
    RefEntry(syntax: "<app name>", detail: "Launch any installed app — fuzzy match, “saf” → Safari"),
    RefEntry(syntax: "<quick link name>", detail: "Open your saved links (edit them in Settings)"),
    RefEntry(syntax: "<task name>", detail: "⏎ marks the open task done — or pick its Track action"),
    RefEntry(syntax: "<note or clipboard text>", detail: "Find notes by title, re-copy clipboard history"),
    RefEntry(syntax: "stop", detail: "Stop Focus Timer / Stop Tracking appear while running"),
    RefEntry(syntax: "send daily summary", detail: "Hours, tasks & streak to your Discord webhook"),
    RefEntry(syntax: "clear completed tasks", detail: "Housekeeping for the task list"),
    RefEntry(syntax: "clear clipboard history", detail: "Forget everything copied so far"),
    RefEntry(syntax: "edit quick links", detail: "Opens links.json to add your own"),
    RefEntry(syntax: "quit command central", detail: "Bye"),
]

private let systemRefs: [RefEntry] = [
    RefEntry(syntax: "lock screen", detail: "Displays sleep → password lock"),
    RefEntry(syntax: "sleep mac", detail: "Full system sleep"),
    RefEntry(syntax: "snip area · window · full", detail: "Screenshots with markup editor — ⇧⌘S works anywhere"),
    RefEntry(syntax: "empty trash", detail: "Via Finder (asks permission once)"),
    RefEntry(syntax: "toggle dark mode", detail: "System-wide appearance switch"),
    RefEntry(syntax: "copy ip", detail: "Local IP → clipboard + notification"),
    RefEntry(syntax: "wifi on  ·  wifi off", detail: "Toggles the Wi-Fi radio"),
    RefEntry(syntax: "downloads · desktop · documents", detail: "Open the common folders in Finder"),
    RefEntry(syntax: "system settings", detail: "Open System Settings"),
    RefEntry(syntax: "activity monitor", detail: "Open Activity Monitor"),
    RefEntry(syntax: "refresh weather", detail: "Force a weather & quake data refresh"),
]

// MARK: - Sub-tabs

private enum CommandsSection: String, CaseIterable, Identifiable {
    case typeAhead = "Type-Ahead"
    case actions = "Actions"
    case system = "System"
    case custom = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .typeAhead: return "keyboard"
        case .actions: return "bolt"
        case .system: return "gearshape"
        case .custom: return "wand.and.stars"
        }
    }

    var entries: [RefEntry] {
        switch self {
        case .typeAhead: return typeAheadRefs
        case .actions: return actionRefs
        case .system: return systemRefs
        case .custom: return []
        }
    }
}

struct CommandsTabView: View {
    @EnvironmentObject private var custom: CustomCommandStore

    @State private var section: CommandsSection = .typeAhead
    @State private var filter = ""

    @State private var newTitle = ""
    @State private var newKeywords = ""
    @State private var newKind: CustomCommand.Kind = .url
    @State private var newValue = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                subTabBar
                Spacer()
                if section != .custom {
                    TextField("Filter…", text: $filter)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 170)
                }
            }
            switch section {
            case .custom: customSection
            default: referenceGrid(section.entries)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Sub-tab bar

    private var subTabBar: some View {
        HStack(spacing: 4) {
            ForEach(CommandsSection.allCases) { item in
                let isSelected = section == item
                Button {
                    withAnimation(.snappy(duration: 0.2)) { section = item }
                } label: {
                    Label(item == .custom ? "Custom · \(custom.commands.count)" : item.rawValue,
                          systemImage: item.icon)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSelected ? Theme.accent.opacity(0.28) : Color.white.opacity(0.05),
                                    in: Capsule())
                        .foregroundStyle(isSelected ? .white : Color.secondary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Reference sections

    private func matches(_ entry: RefEntry) -> Bool {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return entry.syntax.lowercased().contains(needle)
            || entry.detail.lowercased().contains(needle)
    }

    private func referenceGrid(_ entries: [RefEntry]) -> some View {
        let visible = entries.filter(matches)
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 10)],
                      alignment: .leading, spacing: 10) {
                ForEach(visible) { entry in
                    RefCard(entry: entry)
                }
            }
            if visible.isEmpty {
                Text("Nothing matches “\(filter)”")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 40)
            }
            Text("Everything runs from your global hotkey, anywhere on your Mac — plus one secret command you already know 😉")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .padding(.bottom, 6)
        }
    }

    // MARK: - Custom commands

    // Side-by-side when the window is wide enough, stacked when it isn't —
    // never a fixed layout that can run off the edge.
    private var customSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                creatorCard
                    .frame(width: 350)
                customList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ScrollView {
                VStack(spacing: 14) {
                    creatorCard
                    customGrid
                }
            }
        }
    }

    private var creatorCard: some View {
        Card(title: "New Command", systemImage: "plus.circle") {
            VStack(spacing: 8) {
                TextField("Title (shown in the palette)", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                TextField("Keywords to match (e.g. “mail uni”)", text: $newKeywords)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Picker("", selection: $newKind) {
                    ForEach(CustomCommand.Kind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                TextField(placeholder, text: $newValue)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onSubmit(add)
                Button("Add Command", action: add)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .disabled(newTitle.isEmpty || newValue.isEmpty)
                Text("It appears in the palette instantly. Tip: ask Claude in the Terminal tab to write a shell one-liner, then paste it here as a Run Shell command.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var customList: some View {
        if custom.commands.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("No custom commands yet — create your first one on the left.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                customGrid
            }
        }
    }

    private var customGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 10)],
                  alignment: .leading, spacing: 10) {
            ForEach(custom.commands) { command in
                CustomCommandCard(command: command) {
                    custom.remove(command.id)
                }
            }
        }
    }

    private var placeholder: String {
        switch newKind {
        case .url: return "URL — e.g. mail.google.com"
        case .shell: return "Command — e.g. say \"hello\""
        case .app: return "App name — e.g. Discord"
        case .folder: return "Path — e.g. ~/Claude/Maths"
        }
    }

    private func add() {
        custom.add(title: newTitle, keywords: newKeywords, kind: newKind, value: newValue)
        newTitle = ""
        newKeywords = ""
        newValue = ""
    }
}

// MARK: - Cards

private struct RefCard: View {
    let entry: RefEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.syntax)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(entry.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.cardStroke, lineWidth: 1))
    }
}

private struct CustomCommandCard: View {
    let command: CustomCommand
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: command.kind.icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(command.value)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                if !command.keywords.isEmpty {
                    Text("matches: \(command.keywords)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Button("Test") { command.run() }
                    .controlSize(.mini)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Delete this command")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.cardStroke, lineWidth: 1))
    }
}
