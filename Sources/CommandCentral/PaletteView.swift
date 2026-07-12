import AppKit
import SwiftUI

struct PaletteView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var timer: TimerManager

    @State private var query = ""
    @State private var results: [Command] = []
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private let rowHeight: CGFloat = 40
    private let maxVisibleRows = 8

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            resultsList
            Divider()
            footer
        }
        .frame(width: 620)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.separator, lineWidth: 1))
        .tint(settings.accent.color)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            state.paletteResize(size)
        }
        .onReceive(NotificationCenter.default.publisher(for: .paletteDidShow)) { _ in
            query = ""
            selection = 0
            results = state.engine.results(for: "")
            searchFocused = true
        }
        .onChange(of: query) {
            results = state.engine.results(for: query)
            selection = 0
        }
        .onExitCommand { state.hidePalette() }
    }

    private var searchBar: some View {
        HStack(spacing: 11) {
            Image(systemName: "command.square.fill")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
            TextField("Type a command…  (“task buy milk” adds a task)", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .light))
                .focused($searchFocused)
                .onSubmit { runSelected() }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
            if timer.isRunning {
                Label(timer.remainingText, systemImage: "timer")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // The list is exactly as tall as its rows (capped), so the whole
    // palette hugs its content instead of floating in a fixed-size box.
    private var listHeight: CGFloat {
        let count = max(1, min(results.count, maxVisibleRows))
        return CGFloat(count) * rowHeight + CGFloat(max(0, count - 1)) * 2 + 12
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
                        Text("No matches — try an app name, “g <search>”, or a calculation")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(height: rowHeight)
                    }
                }
                .padding(6)
            }
            .frame(height: listHeight)
            .onChange(of: selection) {
                proxy.scrollTo(clampedSelection)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
            Spacer()
            Text("↑↓ select · ⏎ run · esc close")
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func row(_ command: Command, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            iconView(command.icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight)
        .background(isSelected ? Color.accentColor.opacity(0.22) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func iconView(_ icon: Command.Icon) -> some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 14))
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)
        case .file(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 24, height: 24)
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
            // Recompute so the list reflects whatever the command just changed.
            results = state.engine.results(for: query)
            selection = min(clampedSelection, max(0, results.count - 1))
        } else {
            state.hidePalette()
        }
    }
}
