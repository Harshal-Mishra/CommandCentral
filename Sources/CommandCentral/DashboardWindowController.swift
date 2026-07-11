import AppKit
import SwiftUI

final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    private let state: AppState

    init(state: AppState) {
        self.state = state
        let content = DashboardView()
            .environmentObject(state)
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
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Command Central"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1000, height: 660))
        window.contentMinSize = NSSize(width: 880, height: 560)
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
        state.stats.startMonitoring()
        state.media.startMonitoring()
        state.windows.startMonitoring()
        state.weather.startMonitoring()
        state.quakes.startMonitoring()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        state.stats.stopMonitoring()
        state.media.stopMonitoring()
        state.windows.stopMonitoring()
        state.weather.stopMonitoring()
        state.quakes.stopMonitoring()
    }
}
