import CryptoKit
import Foundation

/// Password-protected diary. Entries are AES-GCM encrypted on disk with a
/// key derived from your password — no password, no pages.
final class JournalStore: ObservableObject {
    @Published private(set) var unlocked = false
    @Published private(set) var entries: [String: String] = [:]  // "yyyy-MM-dd" → text

    private var key: SymmetricKey?
    private var fileURL: URL { Storage.directory.appendingPathComponent("journal.enc") }

    var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private func derive(_ password: String) -> SymmetricKey {
        SymmetricKey(data: Data(SHA256.hash(data: Data(("cc-journal:" + password).utf8))))
    }

    /// First-time setup.
    func create(password: String) -> Bool {
        guard !password.isEmpty else { return false }
        key = derive(password)
        entries = [:]
        unlocked = true
        return save()
    }

    func unlock(password: String) -> Bool {
        let candidate = derive(password)
        guard let blob = try? Data(contentsOf: fileURL),
              let box = try? AES.GCM.SealedBox(combined: blob),
              let data = try? AES.GCM.open(box, using: candidate),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return false }
        key = candidate
        entries = decoded
        unlocked = true
        return true
    }

    /// Wipes the decrypted pages from memory.
    func lock() {
        unlocked = false
        key = nil
        entries = [:]
    }

    func text(for day: Date) -> String {
        entries[Self.dayKey(day)] ?? ""
    }

    func setText(_ text: String, for day: Date) {
        let dayKey = Self.dayKey(day)
        guard entries[dayKey] != text else { return }
        if text.isEmpty {
            entries.removeValue(forKey: dayKey)
        } else {
            entries[dayKey] = text
        }
        save()
    }

    var pageCount: Int { entries.count }

    @discardableResult
    private func save() -> Bool {
        guard let key,
              let data = try? JSONEncoder().encode(entries),
              let sealed = try? AES.GCM.seal(data, using: key),
              let combined = sealed.combined else { return false }
        return (try? combined.write(to: fileURL, options: .atomic)) != nil
    }
}
