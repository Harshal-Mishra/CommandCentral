import Foundation

/// Live system overview: top processes, CPU/memory summary, battery.
final class SystemStats: ObservableObject {
    struct ProcessRow: Identifiable {
        let pid: Int
        let cpu: Double
        let mem: Double
        let name: String
        var id: Int { pid }
    }

    @Published private(set) var processes: [ProcessRow] = []
    @Published private(set) var cpuSummary = "—"
    @Published private(set) var memSummary = "—"
    @Published private(set) var battery: String?
    @Published private(set) var diskSummary = "—"
    @Published private(set) var uptimeText = "—"

    private var timer: Timer?
    private var refreshing = false

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
        guard !refreshing else { return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let ps = Self.shell("/bin/ps", ["-Aceo", "pid,pcpu,pmem,comm", "-r"])
            let top = Self.shell("/usr/bin/top", ["-l", "1", "-n", "0", "-s", "0"])
            let batt = Self.shell("/usr/bin/pmset", ["-g", "batt"])

            let rows = Self.parseProcesses(ps)
            let (cpu, mem) = Self.parseTop(top)
            let battery = Self.parseBattery(batt)
            let disk = Self.diskUsage()
            let uptime = Self.uptime()

            DispatchQueue.main.async {
                guard let self else { return }
                self.processes = rows
                self.cpuSummary = cpu
                self.memSummary = mem
                self.battery = battery
                self.diskSummary = disk
                self.uptimeText = uptime
                self.refreshing = false
            }
        }
    }

    /// Sends SIGTERM to a process (same as Activity Monitor's Quit).
    func terminate(pid: Int) {
        kill(pid_t(pid), SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Parsing

    private static func parseProcesses(_ output: String) -> [ProcessRow] {
        output.split(separator: "\n").dropFirst().prefix(20).compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let mem = Double(parts[2]) else { return nil }
            let name = parts[3...].joined(separator: " ")
            return ProcessRow(pid: pid, cpu: cpu, mem: mem, name: name)
        }
    }

    private static func parseTop(_ output: String) -> (String, String) {
        var cpu = "—"
        var mem = "—"
        for line in output.split(separator: "\n") {
            if line.hasPrefix("CPU usage:") {
                // "CPU usage: 6.89% user, 13.79% sys, 79.31% idle"
                if let idlePart = line.components(separatedBy: ", ").last,
                   let idle = Double(idlePart.replacingOccurrences(of: "% idle", with: "").trimmingCharacters(in: .whitespaces)) {
                    cpu = String(format: "%.0f%% busy", 100 - idle)
                }
            } else if line.hasPrefix("PhysMem:") {
                // "PhysMem: 15G used (2758M wired, ...), 240M unused."
                let text = line.replacingOccurrences(of: "PhysMem: ", with: "")
                let used = text.components(separatedBy: " used").first ?? "—"
                let unused = text.components(separatedBy: ", ").last?
                    .replacingOccurrences(of: " unused.", with: "") ?? ""
                mem = unused.isEmpty ? used : "\(used) used · \(unused) free"
            }
        }
        return (cpu, mem)
    }

    private static func parseBattery(_ output: String) -> String? {
        guard let range = output.range(of: #"\d+%"#, options: .regularExpression) else { return nil }
        let percent = String(output[range])
        let state = output.contains("charging") && !output.contains("discharging") ? " ⚡" : ""
        return percent + state
    }

    private static func diskUsage() -> String {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = attrs[.systemFreeSize] as? Int64,
              let total = attrs[.systemSize] as? Int64 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: free)) free of \(formatter.string(fromByteCount: total))"
    }

    private static func uptime() -> String {
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private static func shell(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
