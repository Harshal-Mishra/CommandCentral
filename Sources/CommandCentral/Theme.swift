import SwiftUI

/// App-wide look. `accent` and `background` are mutable so AppSettings can
/// retheme at runtime — views pick the change up when the dashboard
/// re-renders (DashboardView re-ids its subtree on theme changes).
enum Theme {
    static var accent = AccentChoice.blue.color
    static let flame = Color(red: 1.0, green: 0.58, blue: 0.25)

    static var background: BackgroundChoice = .deepBlue

    static var gradient: LinearGradient { background.gradient }

    static let cardFill = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.10)
    static let rowFill = Color.white.opacity(0.05)
}

/// "3h 25m" / "48m" style duration formatting.
func formatHM(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}

/// "1:23:45" stopwatch-style formatting.
func formatHMS(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60
    if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
    return String(format: "%d:%02d", minutes, secs)
}
