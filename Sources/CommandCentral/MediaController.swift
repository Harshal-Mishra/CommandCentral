import AppKit
import Foundation

/// Controls Spotify / Apple Music via AppleScript when one of them is
/// running (this also gives us track info); otherwise falls back to
/// synthesizing hardware media keys, which control whatever player is active.
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

    func startMonitoring() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
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
        refreshVolume()
        guard let player = activePlayer() else {
            nowPlayingTitle = "Nothing playing"
            nowPlayingDetail = "Open Spotify or Music, or use the buttons as media keys"
            isPlaying = false
            return
        }
        let script = """
        tell application "\(player.scriptName)"
            try
                if player state is playing then
                    return "playing|" & name of current track & "|" & artist of current track
                else if player state is paused then
                    return "paused|" & name of current track & "|" & artist of current track
                else
                    return "stopped||"
                end if
            on error
                return "stopped||"
            end try
        end tell
        """
        guard let result = runScript(script)?.stringValue else {
            nowPlayingTitle = "\(player.scriptName) is running"
            nowPlayingDetail = "Grant Automation permission to see track info"
            isPlaying = false
            return
        }
        let parts = result.components(separatedBy: "|")
        let state = parts.first ?? "stopped"
        isPlaying = state == "playing"
        if parts.count >= 3, !parts[1].isEmpty {
            nowPlayingTitle = parts[1]
            nowPlayingDetail = "\(parts[2]) · \(player.scriptName)\(state == "paused" ? " · paused" : "")"
        } else {
            nowPlayingTitle = "\(player.scriptName) idle"
            nowPlayingDetail = "Nothing queued"
        }
    }

    private func refreshVolume() {
        if let value = runScript("output volume of (get volume settings)")?.int32Value {
            volume = Double(value)
        }
    }

    @discardableResult
    private func runScript(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
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
