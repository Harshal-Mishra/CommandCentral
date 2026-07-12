import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var panel: PalettePanel!
    private var hotKey: HotKey?
    private var snipHotKey: HotKey?
    private var dashboard: DashboardWindowController!
    private var journalWindow: JournalWindowController?
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Registers the app in System Settings → Privacy & Security →
        // Screen & System Audio Recording and shows the grant dialog when
        // access is missing (snips need it). Modern TCC only registers the
        // app on a real ScreenCaptureKit attempt — the legacy
        // CGRequestScreenCaptureAccess call is not enough.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            Task {
                _ = try? await SCShareableContent.excludingDesktopWindows(false,
                                                                          onScreenWindowsOnly: true)
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "command.square.fill",
                                   accessibilityDescription: "Command Central")
        }

        let content = PaletteView()
            .environmentObject(state)
            .environmentObject(state.settings)
            .environmentObject(state.tasks)
            .environmentObject(state.timer)
        panel = PalettePanel(contentView: NSHostingView(rootView: content))
        panel.delegate = self

        dashboard = DashboardWindowController(state: state)

        state.hidePalette = { [weak self] in self?.hidePalette() }
        state.paletteResize = { [weak self] size in
            guard let self, self.panel.frame.size != size else { return }
            var frame = self.panel.frame
            frame.origin.y = frame.maxY - size.height
            frame.size = size
            self.panel.setFrame(frame, display: true)
        }
        state.showDashboard = { [weak self] in self?.dashboard.show() }
        state.showDashboardTab = { [weak self] tab in
            self?.dashboard.show()
            NotificationCenter.default.post(name: .openDashboardTab, object: tab.rawValue)
        }
        state.timer.statusUpdate = { [weak self] text in
            self?.statusItem.button?.title = text.map { " " + $0 } ?? ""
        }
        state.showJournal = { [weak self] in
            guard let self else { return }
            if self.journalWindow == nil {
                self.journalWindow = JournalWindowController(state: self.state)
            }
            self.journalWindow?.show()
        }
        state.clipboard.start()
        state.sleep.start()
        state.alarms.start()
        state.stats.startBatteryWatch()
        NotificationCenter.default.addObserver(forName: .alarmFired, object: nil,
                                               queue: .main) { [weak self] _ in
            self?.dashboard.show()
        }

        applyHotKey()
        NotificationCenter.default.addObserver(forName: .hotkeyChanged, object: nil,
                                               queue: .main) { [weak self] _ in
            self?.applyHotKey()
        }

        dashboard.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { dashboard.show() }
        return true
    }

    // MARK: - Hotkey

    private func applyHotKey() {
        let preset = HotKeyPreset.current
        hotKey = HotKey(keyCode: preset.keyCode, modifiers: preset.carbonModifiers) { [weak self] in
            self?.togglePalette()
        }
        if state.settings.snipHotkey {
            snipHotKey = HotKey(keyCode: UInt32(kVK_ANSI_S),
                                modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
                self?.state.startSnip(.rect)
            }
        } else {
            snipHotKey = nil
        }
        buildMainMenu()
        statusItem.menu = buildStatusMenu()
    }

    // MARK: - Menus

    private func buildMainMenu() {
        let preset = HotKeyPreset.current
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Command Central",
                                   action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                                   keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Command Central",
                                   action: #selector(NSApplication.hide(_:)),
                                   keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Command Central",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        for (index, tab) in DashboardTab.allCases.enumerated() {
            let key: String
            if index < 9 {
                key = "\(index + 1)"
            } else if index == 9 {
                key = "0"
            } else {
                key = ""
            }
            let item = NSMenuItem(title: "Open \(tab.title)",
                                  action: #selector(showTabItem(_:)),
                                  keyEquivalent: key)
            item.representedObject = tab.rawValue
            item.target = self
            viewMenu.addItem(item)
        }
        viewMenu.addItem(.separator())
        let paletteItem = NSMenuItem(title: "Show Palette",
                                     action: #selector(showPaletteAction),
                                     keyEquivalent: " ")
        paletteItem.keyEquivalentModifierMask = preset.menuModifiers
        paletteItem.target = self
        viewMenu.addItem(paletteItem)
        viewItem.submenu = viewMenu

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func buildStatusMenu() -> NSMenu {
        let preset = HotKeyPreset.current
        let menu = NSMenu()
        let dashboardItem = NSMenuItem(title: "Open Dashboard",
                                       action: #selector(showDashboardAction),
                                       keyEquivalent: "")
        dashboardItem.target = self
        menu.addItem(dashboardItem)
        let show = NSMenuItem(title: "Show Palette", action: #selector(showPaletteAction), keyEquivalent: " ")
        show.keyEquivalentModifierMask = preset.menuModifiers
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Command Central",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    @objc private func showPaletteAction() { showPalette() }
    @objc private func showDashboardAction() { dashboard.show() }

    @objc private func showTabItem(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String,
           let tab = DashboardTab(rawValue: raw) {
            state.showDashboardTab(tab)
        }
    }

    // MARK: - Palette

    func togglePalette() {
        panel.isVisible ? hidePalette() : showPalette()
    }

    func showPalette() {
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let x = f.midX - panel.frame.width / 2
            let y = f.minY + f.height * 0.72
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .paletteDidShow, object: nil)
    }

    func hidePalette() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === panel {
            hidePalette()
        }
    }
}

extension Notification.Name {
    static let paletteDidShow = Notification.Name("paletteDidShow")
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
}
