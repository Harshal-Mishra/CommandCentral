import SwiftUI

struct TimeTabView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 14) {
                WorldClocksCard()
                Spacer()
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 14) {
                AlarmsCard()
                SleepCard()
                Spacer()
            }
            .frame(width: 360)
        }
    }
}

// MARK: - World clocks

struct WorldClocksCard: View {
    @EnvironmentObject private var clocks: WorldClockStore
    @State private var query = ""

    var body: some View {
        Card(title: "World Clocks", systemImage: "globe",
             trailing: "\(clocks.zones.count)") {
            VStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 5) {
                        ForEach(clocks.zones, id: \.self) { zone in
                            clockRow(zone, date: context.date)
                        }
                    }
                }
                Divider()
                TextField("Add city (e.g. Dubai, Paris, Sydney)…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                if !query.isEmpty {
                    ForEach(WorldClockStore.matches(query), id: \.self) { identifier in
                        Button {
                            clocks.add(identifier)
                            query = ""
                        } label: {
                            HStack {
                                Text(identifier.replacingOccurrences(of: "_", with: " "))
                                    .font(.system(size: 11))
                                Spacer()
                                Image(systemName: "plus")
                                    .font(.system(size: 9))
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func clockRow(_ zone: String, date: Date) -> some View {
        let timeZone = TimeZone(identifier: zone) ?? .current
        var formatter = Date.FormatStyle(date: .omitted, time: .standard)
        formatter.timeZone = timeZone
        let offset = (timeZone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)) / 3600

        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(WorldClockStore.cityName(zone))
                    .font(.system(size: 13, weight: zone == TimeZone.current.identifier ? .semibold : .regular))
                Text(offset == 0 ? "local time" : (offset > 0 ? "+\(offset)h" : "\(offset)h"))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(date, format: formatter)
                .font(.system(size: 16, weight: .light).monospacedDigit())
            Button { clocks.remove(zone) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Alarms

struct AlarmsCard: View {
    @EnvironmentObject private var alarms: AlarmStore
    @State private var newTime = Date()
    @State private var newLabel = ""

    var body: some View {
        Card(title: "Alarms", systemImage: "alarm",
             trailing: "\(alarms.alarms.filter(\.enabled).count) on") {
            VStack(spacing: 6) {
                ForEach(alarms.alarms) { alarm in
                    HStack {
                        Toggle("", isOn: Binding(get: { alarm.enabled },
                                                 set: { _ in alarms.toggle(alarm.id) }))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                        VStack(alignment: .leading, spacing: 0) {
                            Text(alarm.timeText)
                                .font(.system(size: 18, weight: .light).monospacedDigit())
                                .foregroundStyle(alarm.enabled ? .primary : .tertiary)
                            Text(alarm.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { alarms.remove(alarm.id) } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 7))
                }
                if alarms.alarms.isEmpty {
                    Text("Alarms ring while the app is running — a sound plays and the dashboard pops up.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Divider()
                HStack {
                    DatePicker("", selection: $newTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .controlSize(.small)
                    TextField("Label", text: $newLabel)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    Button("Add") {
                        let components = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                        alarms.add(hour: components.hour ?? 7,
                                   minute: components.minute ?? 0,
                                   label: newLabel)
                        newLabel = ""
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Sleep

struct SleepCard: View {
    @EnvironmentObject private var sleep: SleepMonitor

    var body: some View {
        Card(title: "Sleep (Mac Downtime)", systemImage: "bed.double") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sleep.nightSeconds().map { formatHM($0) } ?? "—")
                        .font(.system(size: 30, weight: .light))
                    Text("last night")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 3) {
                    ForEach(sleep.recentNights(7)) { night in
                        HStack {
                            Text(night.date, format: .dateTime.weekday(.abbreviated).day())
                                .font(.system(size: 11))
                                .frame(width: 70, alignment: .leading)
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Theme.accent.gradient)
                                    .frame(width: barWidth(night.seconds, in: geo.size.width),
                                           height: 8)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            .frame(height: 12)
                            Text(night.seconds.map { formatHM($0) } ?? "—")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
                Text("Estimated from when this Mac sleeps and wakes overnight (6 pm–2 pm window, longest gap ≥ 1 h). Builds up from tonight.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func barWidth(_ seconds: Int?, in total: CGFloat) -> CGFloat {
        guard let seconds else { return 2 }
        let fraction = min(1, Double(seconds) / (12 * 3600))
        return max(3, total * fraction)
    }
}
