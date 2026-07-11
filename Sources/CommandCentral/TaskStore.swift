import Foundation

struct TaskItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var done = false
    var createdAt = Date()
    var subject: String?
    var doneAt: Date?
}

final class TaskStore: ObservableObject {
    @Published private(set) var items: [TaskItem] = []

    private var fileURL: URL { Storage.directory.appendingPathComponent("tasks.json") }

    init() {
        load()
    }

    var openTasks: [TaskItem] { items.filter { !$0.done } }

    func add(_ title: String, subject: String? = nil) {
        items.insert(TaskItem(title: title, subject: subject), at: 0)
        save()
    }

    func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].done.toggle()
        items[index].doneAt = items[index].done ? Date() : nil
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clearCompleted() {
        items.removeAll { $0.done }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
