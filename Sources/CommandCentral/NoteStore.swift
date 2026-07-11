import Foundation

struct Note: Codable, Identifiable {
    var id = UUID()
    var text = ""
    var updatedAt = Date()

    var title: String {
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "New Note" : String(trimmed.prefix(40))
    }
}

final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []

    private var fileURL: URL { Storage.directory.appendingPathComponent("notes.json") }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    @discardableResult
    func add(text: String = "") -> UUID {
        let note = Note(text: text)
        notes.insert(note, at: 0)
        save()
        return note.id
    }

    func text(of id: UUID?) -> String {
        guard let id, let note = notes.first(where: { $0.id == id }) else { return "" }
        return note.text
    }

    func update(_ id: UUID?, text: String) {
        guard let id, let index = notes.firstIndex(where: { $0.id == id }) else { return }
        guard notes[index].text != text else { return }
        notes[index].text = text
        notes[index].updatedAt = Date()
        save()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(notes) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
