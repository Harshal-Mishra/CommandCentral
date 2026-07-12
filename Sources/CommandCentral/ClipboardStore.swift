import AppKit
import Foundation

struct ClipItem: Codable, Identifiable {
    var id = UUID()
    var text: String
    var date = Date()
}

/// Watches the general pasteboard and keeps a local history of copied text.
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published var capturing = true

    private var changeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var maxItems = 50
    private let maxLength = 2000

    /// Set from AppSettings; trims existing history when lowered.
    func setLimit(_ limit: Int) {
        maxItems = max(5, limit)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
            save()
        }
    }

    private var fileURL: URL { Storage.directory.appendingPathComponent("clipboard.json") }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) {
            items = decoded
        }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        guard capturing,
              let text = pasteboard.string(forType: .string)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              text != items.first?.text else { return }
        items.insert(ClipItem(text: String(text.prefix(maxLength))), at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        save()
    }

    func copy(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        changeCount = pasteboard.changeCount
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
