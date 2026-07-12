import AppKit
import Foundation

/// Controls Spotify / Apple Music via AppleScript when one of them is
/// running (this also gives us track info); otherwise falls back to
/// synthesizing hardware media keys, which control whatever player is active.
///
/// All scripting runs through `osascript` on a background queue — AppleScript
/// can take hundreds of milliseconds and must never block the UI.
final class MediaController: ObservableObject {
    @Published private(set) var nowPlayingTitle = "Nothing playing"
    @Published private(set) var nowPlayingDetail = "Open Spotify or Music, or use the buttons as media keys"
    @Published private(set) var isPlaying = false
    @Published var volume: Double = 50

    private struct Player {
        let bundleID: String
        let scriptName: String
    }

    private let players = [
        Player(bundleID: "com.spotify.client", scriptName: "Spotify"),
        Player(bundleID: "com.apple.Music", scriptName: "Music"),
    ]

    private var timer: Timer?
    private let scriptQueue = DispatchQueue(label: "CommandCentral.media-scripts", qos: .userInitiated)

    func startMonitoring() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = 1
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Controls

    func playPause() { control(scriptCommand: "playpause", fallbackKey: .playPause) }
    func next() { control(scriptCommand: "next track", fallbackKey: .next) }
    func previous() { control(scriptCommand: "previous track", fallbackKey: .previous) }

    private func control(scriptCommand: String, fallbackKey: MediaKey) {
        if let player = activePlayer() {
            runScript("tell application \"\(player.scriptName)\" to \(scriptCommand)")
        } else {
            fallbackKey.post()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    func setVolume(_ value: Double) {
        volume = value
        runScript("set volume output volume \(Int(value.rounded()))")
    }

    // MARK: - State

    private func activePlayer() -> Player? {
        players.first {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty
        }
    }

    func refresh() {
        guard let player = activePlayer() else {
            nowPlayingTitle = "Nothing playing"
            nowPlayingDetail = "Open Spotify or Music, or use the buttons as media keys"
            isPlaying = false
            runScript("output volume of (get volume settings)") { [weak self] output in
                if let output, let value = Int(output) {
                    self?.volume = Double(value)
                }
            }
            return
        }
        // One round-trip fetches volume + player state + track info together.
        let script = """
        set vol to output volume of (get volume settings)
        tell application "\(player.scriptName)"
            try
                if player state is playing then
                    return (vol as text) & "|playing|" & name of current track & "|" & artist of current track
                else if player state is paused then
                    return (vol as text) & "|paused|" & name of current track & "|" & artist of current track
                else
                    return (vol as text) & "|stopped||"
                end if
            on error
                return (vol as text) & "|stopped||"
            end try
        end tell
        """
        runScript(script) { [weak self] output in
            guard let self else { return }
            guard let output else {
                self.nowPlayingTitle = "\(player.scriptName) is running"
                self.nowPlayingDetail = "Grant Automation permission to see track info"
                self.isPlaying = false
                return
            }
            let parts = output.components(separatedBy: "|")
            if let value = parts.first.flatMap({ Int($0) }) {
                self.volume = Double(value)
            }
            let state = parts.count >= 2 ? parts[1] : "stopped"
            self.isPlaying = state == "playing"
            if parts.count >= 4, !parts[2].isEmpty {
                self.nowPlayingTitle = parts[2]
                self.nowPlayingDetail = "\(parts[3]) · \(player.scriptName)\(state == "paused" ? " · paused" : "")"
            } else {
                self.nowPlayingTitle = "\(player.scriptName) idle"
                self.nowPlayingDetail = "Nothing queued"
            }
        }
    }

    /// Runs AppleScript via osascript off the main thread; the completion
    /// (if any) is delivered back on the main thread with trimmed stdout,
    /// or nil when the script failed.
    private func runScript(_ source: String, completion: ((String?) -> Void)? = nil) {
        scriptQueue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            var output: String?
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    output = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {
                output = nil
            }
            if let completion {
                DispatchQueue.main.async { completion(output) }
            }
        }
    }
}

/// Synthesizes hardware media key presses (F7/F8/F9 equivalents).
enum MediaKey: Int32 {
    case playPause = 16   // NX_KEYTYPE_PLAY
    case next = 17        // NX_KEYTYPE_NEXT
    case previous = 18    // NX_KEYTYPE_PREVIOUS

    func post() {
        for down in [true, false] {
            let data1 = Int((Int32(rawValue) << 16) | ((down ? 0xA : 0xB) << 8))
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let event = NSEvent.otherEvent(with: .systemDefined,
                                           location: .zero,
                                           modifierFlags: flags,
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: 0,
                                           context: nil,
                                           subtype: 8,
                                           data1: data1,
                                           data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
