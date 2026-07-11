import AppKit
import SwiftUI

struct WindowsView: View {
    @EnvironmentObject private var windows: WindowsManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card(title: "Running Apps", systemImage: "square.grid.3x3",
                     trailing: "\(windows.apps.count)") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)],
                              spacing: 10) {
                        ForEach(windows.apps) { app in
                            appCell(app)
                        }
                    }
                }

                Card(title: "Windows on This Desktop", systemImage: "macwindow",
                     trailing: "\(currentWindows.count)") {
                    windowRows(currentWindows,
                               empty: "No app windows on this desktop")
                }

                Card(title: "Other Desktops & Minimized", systemImage: "rectangle.on.rectangle",
                     trailing: "\(otherWindows.count)") {
                    windowRows(otherWindows,
                               empty: "Nothing on other Spaces or in the Dock")
                }

                if !windows.titlesGranted {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                        Text("Window titles need the Screen Recording permission (macOS rule). App names still work without it.")
                            .font(.system(size: 11))
                        Button("Enable Titles…") { windows.requestTitleAccess() }
                            .controlSize(.small)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                }
            }
        }
        .onAppear { windows.refresh() }
    }

    private var currentWindows: [WindowInfo] { windows.windows.filter(\.onCurrentSpace) }
    private var otherWindows: [WindowInfo] { windows.windows.filter { !$0.onCurrentSpace } }

    private func appCell(_ app: RunningAppInfo) -> some View {
        Button {
            windows.activate(app.pid)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 38, height: 38)
                    } else {
                        Image(systemName: "app")
                            .font(.system(size: 30))
                    }
                    if app.isActive {
                        Circle()
                            .fill(.green)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    }
                }
                Text(app.name)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .opacity(app.isHidden ? 0.4 : 1)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(app.isHidden ? "Unhide" : "Hide") { windows.toggleHidden(app.pid) }
            Button("Quit", role: .destructive) { windows.quit(app.pid) }
        }
        .help(app.isHidden ? "\(app.name) (hidden) — click to show" : app.name)
    }

    @ViewBuilder
    private func windowRows(_ list: [WindowInfo], empty: String) -> some View {
        if list.isEmpty {
            Text(empty)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 3) {
                ForEach(list) { window in
                    HStack(spacing: 8) {
                        Text(window.title.isEmpty ? window.app : window.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        if !window.title.isEmpty {
                            Text(window.app)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("Show") { windows.activate(window.pid) }
                            .controlSize(.mini)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}
