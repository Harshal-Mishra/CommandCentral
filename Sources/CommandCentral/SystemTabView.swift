import SwiftUI

struct SystemTabView: View {
    @EnvironmentObject private var stats: SystemStats

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                statTile("CPU", stats.cpuSummary, "cpu")
                statTile("Memory", stats.memSummary, "memorychip")
                statTile("Disk", stats.diskSummary, "internaldrive")
                statTile("Uptime", stats.uptimeText, "power")
                if let battery = stats.battery {
                    statTile("Battery", battery, "battery.75percent")
                }
            }
            ProcessesCard(showKill: true)
                .frame(maxHeight: .infinity)
        }
    }

    private func statTile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.cardStroke, lineWidth: 1))
    }
}
