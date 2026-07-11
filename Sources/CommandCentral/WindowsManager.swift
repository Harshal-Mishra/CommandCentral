import AppKit
import CoreGraphics
import Foundation

struct RunningAppInfo: Identifiable {
    let pid: Int32
    let name: String
    let icon: NSImage?
    let isActive: Bool
    let isHidden: Bool
    var id: Int32 { pid }
}

struct WindowInfo: Identifiable {
    let id: Int
    let title: String
    let app: String
    let pid: Int32
    let onCurrentSpace: Bool
}

/// Lists running apps and their windows, including windows on other
/// desktops (Spaces) and minimized ones.
final class WindowsManager: ObservableObject {
    @Published private(set) var apps: [RunningAppInfo] = []
    @Published private(set) var windows: [WindowInfo] = []
    @Published private(set) var titlesGranted = false

    private var timer: Timer?

    func startMonitoring() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        titlesGranted = CGPreflightScreenCaptureAccess()

        let regularApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        apps = regularApps.map {
            RunningAppInfo(pid: $0.processIdentifier,
                           name: $0.localizedName ?? "App",
                           icon: $0.icon,
                           isActive: $0.isActive,
                           isHidden: $0.isHidden)
        }
        .sorted { $0.name.lowercased() < $1.name.lowercased() }

        let regularPIDs = Set(regularApps.map(\.processIdentifier))
        let ownPID = ProcessInfo.processInfo.processIdentifier

        let onScreenIDs = Set(windowDictionaries([.optionOnScreenOnly, .excludeDesktopElements])
            .compactMap { $0[kCGWindowNumber as String] as? Int })

        var result: [WindowInfo] = []
        for dict in windowDictionaries([.optionAll, .excludeDesktopElements]) {
            guard (dict[kCGWindowLayer as String] as? Int) == 0,
                  let pid = dict[kCGWindowOwnerPID as String] as? Int32,
                  regularPIDs.contains(pid),
                  pid != ownPID,
                  let number = dict[kCGWindowNumber as String] as? Int else { continue }
            if let bounds = dict[kCGWindowBounds as String] as? [String: Any],
               let width = bounds["Width"] as? Double,
               let height = bounds["Height"] as? Double,
               width < 80 || height < 50 { continue }
            let owner = dict[kCGWindowOwnerName as String] as? String ?? "App"
            let title = dict[kCGWindowName as String] as? String ?? ""
            result.append(WindowInfo(id: number,
                                     title: title,
                                     app: owner,
                                     pid: pid,
                                     onCurrentSpace: onScreenIDs.contains(number)))
        }
        windows = result.sorted {
            if $0.onCurrentSpace != $1.onCurrentSpace { return $0.onCurrentSpace }
            return $0.app.lowercased() < $1.app.lowercased()
        }
    }

    private func windowDictionaries(_ options: CGWindowListOption) -> [[String: Any]] {
        (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
    }

    // MARK: - Actions

    func requestTitleAccess() {
        CGRequestScreenCaptureAccess()
    }

    private func app(for pid: Int32) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: pid)
    }

    func activate(_ pid: Int32) {
        guard let app = app(for: pid) else { return }
        if app.isHidden { app.unhide() }
        app.activate(options: [.activateAllWindows])
    }

    func toggleHidden(_ pid: Int32) {
        guard let app = app(for: pid) else { return }
        if app.isHidden {
            app.unhide()
        } else {
            app.hide()
        }
        refresh()
    }

    func quit(_ pid: Int32) {
        app(for: pid)?.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refresh()
        }
    }
}
