import SwiftUI

private struct RefEntry: Identifiable {
    let syntax: String
    let detail: String
    var id: String { syntax }
}

private let keywordRefs: [RefEntry] = [
    RefEntry(syntax: "task buy notebook", detail: "Add a task"),
    RefEntry(syntax: "note remember this", detail: "Save a quick note"),
    RefEntry(syntax: "focus 45  /  timer 90", detail: "Start a focus timer (minutes, up to 720)"),
    RefEntry(syntax: "track maths", detail: "Start the study stopwatch on a subject"),
    RefEntry(syntax: "alarm 7:30 wake up", detail: "Set an alarm with a label"),
    RefEntry(syntax: "discord hello team", detail: "Post to your Discord webhook"),
    RefEntry(syntax: "claude explain closures", detail: "Ask Claude Code in the Terminal tab"),
    RefEntry(syntax: "g swift arrays", detail: "Google search"),
    RefEntry(syntax: "yt lofi beats", detail: "YouTube search"),
    RefEntry(syntax: "wiki fourier transform", detail: "Wikipedia search"),
    RefEntry(syntax: "12*45+8", detail: "Calculator — ⏎ copies the result"),
    RefEntry(syntax: "github.com/harshal", detail: "Any web address opens directly"),
    RefEntry(syntax: "chrome  /  chrome inc", detail: "New Chrome window / incognito on google.com"),
    RefEntry(syntax: "brave  /  brave inc", detail: "New Brave window / private on google.com"),
]

private let actionRefs: [RefEntry] = [
    RefEntry(syntax: "Open <tab name>", detail: "Jump to any tab — Tracker, Weather, Map, Notes…"),
    RefEntry(syntax: "<app name>", detail: "Launch any installed app (fuzzy match, e.g. “saf” → Safari)"),
    RefEntry(syntax: "<quick link name>", detail: "Open your saved links (edit them in Settings)"),
    RefEntry(syntax: "<task name>", detail: "⏎ marks an open task done"),
    RefEntry(syntax: "<note / clipboard text>", detail: "Find notes by title, re-copy clipboard history"),
    RefEntry(syntax: "Lock Screen", detail: "Displays sleep → password lock"),
    RefEntry(syntax: "Sleep Mac", detail: "Full system sleep"),
    RefEntry(syntax: "Screenshot Area → Clipboard", detail: "Drag-select a region"),
    RefEntry(syntax: "Empty Trash", detail: "Via Finder (asks permission once)"),
    RefEntry(syntax: "Toggle Dark Mode", detail: "System-wide appearance"),
    RefEntry(syntax: "Copy IP Address", detail: "Local IP → clipboard + notification"),
    RefEntry(syntax: "Turn Wi-Fi On / Off", detail: "Toggles the Wi-Fi radio"),
    RefEntry(syntax: "Open Downloads / Desktop / Documents", detail: "Common folders"),
    RefEntry(syntax: "System Settings / Activity Monitor", detail: "System utilities"),
    RefEntry(syntax: "Refresh Weather & Quakes", detail: "Force a data refresh"),
    RefEntry(syntax: "Stop Focus Timer / Stop Tracking", detail: "Appear while running"),
    RefEntry(syntax: "Send Daily Summary to Discord", detail: "Hours, tasks, streak"),
    RefEntry(syntax: "Clear Clipboard History / Clear Completed Tasks", detail: "Housekeeping"),
    RefEntry(syntax: "Quit Command Central", detail: "Bye"),
]

struct CommandsTabView: View {
    @EnvironmentObject private var custom: CustomCommandStore

    @State private var newTitle = ""
    @State private var newKeywords = ""
    @State private var newKind: CustomCommand.Kind = .url
    @State private var newValue = ""

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            customCard
                .frame(width: 380)
                .frame(maxHeight: .infinity)
            ScrollView {
                VStack(spacing: 14) {
                    referenceCard(title: "Type-Ahead Commands", icon: "keyboard",
                                  entries: keywordRefs)
                    referenceCard(title: "Actions & Search", icon: "bolt",
                                  entries: actionRefs)
                    Text("…plus one secret command you already know 😉")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func referenceCard(title: String, icon: String, entries: [RefEntry]) -> some View {
        Card(title: title, systemImage: icon) {
            VStack(spacing: 4) {
                ForEach(entries) { entry in
                    HStack(alignment: .top) {
                        Text(entry.syntax)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 250, alignment: .leading)
                        Text(entry.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var customCard: some View {
        Card(title: "Your Custom Commands", systemImage: "wand.and.stars",
             trailing: "\(custom.commands.count)") {
            VStack(spacing: 8) {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(custom.commands) { command in
                            HStack {
                                Image(systemName: command.kind.icon)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(command.title).font(.system(size: 12))
                                    Text(command.value)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Test") { command.run() }
                                    .controlSize(.mini)
                                Button { custom.remove(command.id) } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 7))
                        }
                        if custom.commands.isEmpty {
                            Text("No custom commands yet — create one below. It appears in ⌥Space instantly.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 16)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                Divider()
                VStack(spacing: 6) {
                    Text("New command")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .disabled(newTitle.isEmpty || newValue.isEmpty)
                    Text("Tip: ask Claude in the Terminal tab to write a shell one-liner, then paste it here as a Run Shell command.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxHeight: .infinity)
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
