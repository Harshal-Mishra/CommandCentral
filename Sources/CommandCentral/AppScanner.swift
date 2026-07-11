import Foundation

struct AppEntry {
    let name: String
    let path: String
}

final class AppScanner {
    private(set) var apps: [AppEntry] = []

    private let searchDirectories = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    init() {
        scan()
    }

    func scan() {
        var seen = Set<String>()
        var found: [AppEntry] = []
        let fm = FileManager.default
        for dir in searchDirectories {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let name = String(entry.dropLast(4))
                guard seen.insert(name.lowercased()).inserted else { continue }
                found.append(AppEntry(name: name, path: dir + "/" + entry))
            }
        }
        apps = found.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
