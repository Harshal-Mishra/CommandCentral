import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct SnipItem: Identifiable, Equatable {
    let url: URL
    let date: Date
    var id: String { url.path }
}

/// Captures screenshots Windows-Snipping-Tool-style (frozen-screen overlay
/// with a mode bar — see SnipCaptureSession) into
/// Application Support/CommandCentral/Snips. Every capture is also copied
/// straight to the clipboard.
final class SnipStore: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case rect, freeform, window, full, timed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rect: return "Rectangle"
            case .freeform: return "Freeform"
            case .window: return "Window"
            case .full: return "Full Screen"
            case .timed: return "Full in 3s"
            }
        }

        var icon: String {
            switch self {
            case .rect: return "rectangle.dashed"
            case .freeform: return "lasso"
            case .window: return "macwindow"
            case .full: return "rectangle.inset.filled"
            case .timed: return "timer"
            }
        }

        var subtitle: String {
            switch self {
            case .rect: return "Drag a box — the classic snip"
            case .freeform: return "Draw any shape around it (transparent outside)"
            case .window: return "Click a window to capture it cleanly"
            case .full: return "Whole screen, instantly"
            case .timed: return "Whole screen after a 3-second delay"
            }
        }
    }

    @Published private(set) var snips: [SnipItem] = []
    /// Set after a capture so the Snips tab opens the editor on arrival.
    @Published var pendingEdit: URL?

    private let directory: URL = {
        let dir = Storage.directory.appendingPathComponent("Snips", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        reload()
    }

    func reload() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory,
                                                 includingPropertiesForKeys: [.creationDateKey],
                                                 options: .skipsHiddenFiles)) ?? []
        snips = files
            .filter { $0.pathExtension.lowercased() == "png" }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return SnipItem(url: url, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    /// Runs the capture flow; calls back on main with the saved file (nil
    /// for cancel / text / color outcomes) and whether the editor should
    /// open. Capture is attempted even without permission — the real
    /// ScreenCaptureKit call is what makes macOS register the app in the
    /// Screen Recording list and prompt.
    func capture(_ mode: Mode, completion: @escaping (URL?, Bool) -> Void) {
        switch mode {
        case .full:
            captureFullDisplay(after: 0, completion: completion)
        case .timed:
            captureFullDisplay(after: 3, completion: completion)
        case .rect, .freeform, .window:
            Task { @MainActor in
                SnipCaptureSession.begin(mode: mode) { [weak self] outcome in
                    self?.handleOutcome(outcome, completion: completion)
                }
            }
        }
    }

    private func captureFullDisplay(after delay: TimeInterval,
                                    completion: @escaping (URL?, Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor in
                if let image = await SnipCaptureSession.captureMouseDisplay() {
                    self?.handleOutcome(.image(image, openEditor: true), completion: completion)
                } else {
                    self?.handleOutcome(.cancelled, completion: completion)
                }
            }
        }
    }

    private func handleOutcome(_ outcome: CaptureOutcome, completion: (URL?, Bool) -> Void) {
        switch outcome {
        case .cancelled:
            // Nil + no permission = the capture failed on access, not Esc.
            if !CGPreflightScreenCaptureAccess() {
                showPermissionHelp()
            }
            completion(nil, false)
        case .image(let image, let openEditor):
            if let url = saveImage(image) {
                reload()
                copyToClipboard(url)
                completion(url, openEditor)
            } else {
                completion(nil, false)
            }
        case .text(let text):
            if let text {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                let lines = text.split(separator: "\n").count
                NotificationManager.shared.notify(title: "Text copied 📋",
                                                  body: "\(lines) line\(lines == 1 ? "" : "s") extracted to the clipboard")
            } else {
                NotificationManager.shared.notify(title: "No text found",
                                                  body: "Couldn't read any text in that area")
            }
            completion(nil, false)
        case .color(let hex):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            NotificationManager.shared.notify(title: "\(hex) copied 🎨",
                                              body: "Hex color is on the clipboard")
            completion(nil, false)
        }
    }

    private func saveImage(_ image: CGImage) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = directory.appendingPathComponent("Snip \(formatter.string(from: .now)).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                UTType.png.identifier as CFString,
                                                                1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return url
    }

    /// Screen Recording is required; the grant survives rebuilds now that
    /// builds are signed with the stable "CommandCentral Dev" certificate.
    private func showPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
        Snips need Screen Recording access. Turn on Command Central in \
        System Settings → Privacy & Security → Screen Recording, then quit \
        and reopen the app once. The permission now sticks across updates.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func copyToClipboard(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    func delete(_ item: SnipItem) {
        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        reload()
    }

    func revealInFinder(_ item: SnipItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Snips grouped per day, newest day first — the tab renders these
    /// as sections ("Today", "Yesterday", explicit dates further back).
    var byDay: [(day: Date, label: String, items: [SnipItem])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: snips) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { day in
            let label: String
            if calendar.isDateInToday(day) {
                label = "Today"
            } else if calendar.isDateInYesterday(day) {
                label = "Yesterday"
            } else {
                label = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
            }
            return (day, label, groups[day] ?? [])
        }
    }
}
