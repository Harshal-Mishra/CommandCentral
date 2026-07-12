import AppKit
import Foundation

/// User-defined ⌥Space commands.
struct CustomCommand: Codable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case url, shell, app, folder

        var id: String { rawValue }

        // Segmented controls can't compress below their labels' natural
        // width, so these must stay short — long ones overflow fixed-width
        // cards and get clipped at the window edge.
        var label: String {
            switch self {
            case .url: return "URL"
            case .shell: return "Shell"
            case .app: return "App"
            case .folder: return "Folder"
            }
        }

        var icon: String {
            switch self {
            case .url: return "link"
            case .shell: return "terminal"
            case .app: return "app.badge"
            case .folder: return "folder"
            }
        }
    }

    var id = UUID()
    var title: String
    var keywords: String
    var kind: Kind
    var value: String

    func run() {
        switch kind {
        case .url:
            var urlString = value.trimmingCharacters(in: .whitespaces)
            if !urlString.contains("://") { urlString = "https://" + urlString }
            if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
        case .shell:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", value]
            try? process.run()
        case .app:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", value]
            try? process.run()
        case .folder:
            let expanded = (value as NSString).expandingTildeInPath
            NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
        }
    }
}

final class CustomCommandStore: ObservableObject {
    @Published private(set) var commands: [CustomCommand] = []

    private var fileURL: URL { Storage.directory.appendingPathComponent("custom_commands.json") }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([CustomCommand].self, from: data) {
            commands = decoded
        }
    }

    func add(title: String, keywords: String, kind: CustomCommand.Kind, value: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let cleanValue = value.trimmingCharacters(in: .whitespaces)
        guard !cleanTitle.isEmpty, !cleanValue.isEmpty else { return }
        commands.append(CustomCommand(title: cleanTitle,
                                      keywords: keywords.trimmingCharacters(in: .whitespaces),
                                      kind: kind,
                                      value: cleanValue))
        save()
    }

    func remove(_ id: UUID) {
        commands.removeAll { $0.id == id }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(commands) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
