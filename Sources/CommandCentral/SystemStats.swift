import Darwin
import Foundation

/// Live system overview: top processes, CPU/memory summary, battery.
/// CPU and memory come straight from Mach kernel counters (instant);
/// only the process table and battery shell out, on a background queue.
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
    private var batteryTimer: Timer?
    private var refreshing = false
    private var previousTicks: (busy: UInt64, total: UInt64)?

    func startMonitoring() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = 1
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Cheap always-on poll so the dashboard header can show battery
    /// without the full System-tab refresh running.
    func startBatteryWatch() {
        guard batteryTimer == nil else { return }
        refreshBattery()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshBattery()
        }
        batteryTimer?.tolerance = 10
    }

    private func refreshBattery() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let text = Self.parseBattery(Self.shell("/usr/bin/pmset", ["-g", "batt"]))
            DispatchQueue.main.async { self?.battery = text }
        }
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let cpu = cpuSummaryNow()
        let mem = Self.memorySummary()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let ps = Self.shell("/bin/ps", ["-Aceo", "pid,pcpu,pmem,comm", "-r"])
            let batt = Self.parseBattery(Self.shell("/usr/bin/pmset", ["-g", "batt"]))
            let rows = Self.parseProcesses(ps)
            let disk = Self.diskUsage()
            let uptime = Self.uptime()

            DispatchQueue.main.async {
                guard let self else { return }
                self.processes = rows
                self.cpuSummary = cpu
                self.memSummary = mem
                self.battery = batt
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

    // MARK: - CPU (host_statistics tick deltas)

    private func cpuSummaryNow() -> String {
        guard let ticks = Self.cpuTicks() else { return cpuSummary }
        let busy = ticks.user + ticks.system + ticks.nice
        let total = busy + ticks.idle
        defer { previousTicks = (busy, total) }
        guard let previous = previousTicks, total > previous.total, busy >= previous.busy else {
            return cpuSummary
        }
        let percent = Double(busy - previous.busy) / Double(total - previous.total) * 100
        return String(format: "%.0f%% busy", percent)
    }

    private static func cpuTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size
                                           / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1),
                UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3))
    }

    // MARK: - Memory (vm_statistics64)

    private static func memorySummary() -> String {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
                                           / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "—" }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count)
                    + UInt64(stats.compressor_page_count)) * UInt64(pageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        let free = total > used ? total - used : 0
        return "\(formatter.string(fromByteCount: Int64(used))) used · \(formatter.string(fromByteCount: Int64(free))) free"
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
