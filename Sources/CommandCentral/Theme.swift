import SwiftUI

/// Deep-blue gradient theme.
enum Theme {
    static let accent = Color(red: 0.38, green: 0.65, blue: 1.0)
    static let flame = Color(red: 1.0, green: 0.58, blue: 0.25)

    static let backgroundTop = Color(red: 0.05, green: 0.11, blue: 0.28)
    static let backgroundMid = Color(red: 0.03, green: 0.06, blue: 0.18)
    static let backgroundBottom = Color(red: 0.01, green: 0.02, blue: 0.09)

    static var gradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundMid, backgroundBottom],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
    }

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
