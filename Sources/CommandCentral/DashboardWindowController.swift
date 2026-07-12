import AppKit
import SwiftUI

final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    private let state: AppState

    init(state: AppState) {
        self.state = state
        let content = DashboardView()
            .environmentObject(state)
            .environmentObject(state.settings)
            .environmentObject(state.tasks)
            .environmentObject(state.timer)
            .environmentObject(state.media)
            .environmentObject(state.stats)
            .environmentObject(state.notes)
            .environmentObject(state.clipboard)
            .environmentObject(state.windows)
            .environmentObject(state.home)
            .environmentObject(state.links)
            .environmentObject(state.tracker)
            .environmentObject(state.events)
            .environmentObject(state.location)
            .environmentObject(state.weather)
            .environmentObject(state.quakes)
            .environmentObject(state.clocks)
            .environmentObject(state.alarms)
            .environmentObject(state.sleep)
            .environmentObject(state.tabPrefs)
            .environmentObject(state.custom)
            .environmentObject(state.snips)
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Command Central"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // Fit the default size to the actual screen so small displays never
        // start with a window that runs past the edges.
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let width = min(1000, screen.width - 40)
        let height = min(660, screen.height - 60)
        window.setContentSize(NSSize(width: width, height: height))
        window.contentMinSize = NSSize(width: min(880, width), height: min(560, height))
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CommandCentralDashboard")
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        state.updateMonitors(for: state.currentTab)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        state.updateMonitors(for: nil)
    }
}
