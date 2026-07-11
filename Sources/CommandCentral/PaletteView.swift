import AppKit
import SwiftUI

struct PaletteView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var tasks: TaskStore
    @EnvironmentObject private var timer: TimerManager

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private var results: [Command] { state.engine.results(for: query) }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            resultsList
        }
        .frame(width: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.separator, lineWidth: 1))
        .frame(maxHeight: .infinity, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: .paletteDidShow)) { _ in
            query = ""
            selection = 0
            searchFocused = true
        }
        .onChange(of: query) { selection = 0 }
        .onExitCommand { state.hidePalette() }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "command.square.fill")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            TextField("Type a command…  (“task buy milk” adds a task)", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .light))
                .focused($searchFocused)
                .onSubmit { runSelected() }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
            if timer.isRunning {
                Label(timer.remainingText, systemImage: "timer")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                        row(command, isSelected: index == clampedSelection)
                            .id(index)
                            .onTapGesture {
                                selection = index
                                runSelected()
                            }
                    }
                    if results.isEmpty {
                        Text("No matches")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 340)
            .onChange(of: selection) {
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(clampedSelection)
                }
            }
        }
    }

    private func row(_ command: Command, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            iconView(command.icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(.system(size: 15))
                    .lineLimit(1)
                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.22) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func iconView(_ icon: Command.Icon) -> some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 16))
                .frame(width: 26, height: 26)
                .foregroundStyle(.secondary)
        case .file(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 26, height: 26)
        }
    }

    private var clampedSelection: Int {
        results.isEmpty ? 0 : min(selection, results.count - 1)
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (clampedSelection + delta + results.count) % results.count
    }

    private func runSelected() {
        guard !results.isEmpty else { return }
        let command = results[clampedSelection]
        command.action()
        if command.keepOpen {
            if command.id == "add-task" { query = "" }
        } else {
            state.hidePalette()
        }
    }
}
