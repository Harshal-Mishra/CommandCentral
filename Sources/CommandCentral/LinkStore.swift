import Foundation

struct QuickLink: Codable, Identifiable {
    var title: String
    var url: String
    var id: String { url }
}

final class LinkStore: ObservableObject {
    @Published private(set) var links: [QuickLink] = []

    var fileURL: URL { Storage.directory.appendingPathComponent("links.json") }

    private static let defaults: [QuickLink] = [
        QuickLink(title: "My Website", url: "https://harshal-mishra.github.io"),
        QuickLink(title: "Gmail", url: "https://mail.google.com"),
        QuickLink(title: "Maths Folder", url: "file:///Users/harshalmishra/Claude/Maths"),
        QuickLink(title: "Claude Folder", url: "file:///Users/harshalmishra/Claude"),
    ]

    init() {
        load()
    }

    func add(title: String, url: String) {
        var normalized = url.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if !normalized.contains("://") {
            normalized = "https://" + normalized
        }
        guard !links.contains(where: { $0.url == normalized }) else { return }
        links.append(QuickLink(title: title.trimmingCharacters(in: .whitespaces), url: normalized))
        save()
    }

    func remove(_ id: String) {
        links.removeAll { $0.id == id }
        save()
    }

    func reload() { load() }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([QuickLink].self, from: data) {
            links = decoded
        } else {
            links = Self.defaults
            save()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(links) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
