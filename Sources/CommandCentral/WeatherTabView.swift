import SwiftUI

struct WeatherTabView: View {
    @EnvironmentObject private var weather: WeatherStore
    @EnvironmentObject private var quakes: QuakeStore
    @EnvironmentObject private var location: LocationStore
    @EnvironmentObject private var state: AppState

    var body: some View {
        if !location.isSet {
            VStack(spacing: 12) {
                Text("🌍").font(.system(size: 40))
                Text("Set your location to enable weather, sunrise/sunset, rain and earthquake alerts.")
                    .foregroundStyle(.secondary)
                Button("Set Location in Settings") { state.showDashboardTab(.settings) }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    currentCard
                    SunCard()
                    Spacer()
                }
                .frame(width: 340)
                VStack(spacing: 14) {
                    rainCard
                    alertsCard
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                weather.refresh()
                quakes.refresh()
            }
        }
    }

    private var currentCard: some View {
        Card(title: location.name ?? "Weather", systemImage: "cloud.sun",
             trailing: weather.lastUpdated.map { "updated " + $0.formatted(date: .omitted, time: .shortened) }) {
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    Text(weather.emoji).font(.system(size: 44))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(weather.temperature.map { "\(Int($0.rounded()))°C" } ?? "—")
                            .font(.system(size: 36, weight: .light))
                        Text(weather.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Divider()
                HStack {
                    detail("Feels", weather.feelsLike.map { "\(Int($0.rounded()))°" } ?? "—")
                    detail("Humidity", weather.humidity.map { "\($0)%" } ?? "—")
                    detail("Wind", weather.windSpeed.map { "\(Int($0)) km/h" } ?? "—")
                    detail("Hi/Lo", highLow)
                }
                Button("Refresh") {
                    weather.refresh()
                    quakes.refresh()
                }
                .controlSize(.small)
            }
        }
    }

    private var highLow: String {
        guard let max = weather.tempMax, let min = weather.tempMin else { return "—" }
        return "\(Int(max.rounded()))°/\(Int(min.rounded()))°"
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 12, weight: .medium))
        }
        .frame(maxWidth: .infinity)
    }

    private var rainCard: some View {
        Card(title: "Rain — Next 12 Hours", systemImage: "cloud.rain") {
            if weather.hourlyRain.isEmpty {
                Text("No forecast loaded yet").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(weather.hourlyRain) { hour in
                        VStack(spacing: 3) {
                            Text("\(hour.probability)")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(hour.probability >= 60 ? AnyShapeStyle(Theme.flame.gradient)
                                                             : AnyShapeStyle(Theme.accent.gradient))
                                .frame(height: max(3, CGFloat(hour.probability)))
                            Text(hour.date, format: .dateTime.hour())
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 140, alignment: .bottom)
            }
        }
    }

    private var alertsCard: some View {
        let all = weather.alerts + quakes.alerts
        return Card(title: "Alerts", systemImage: "exclamationmark.triangle",
                    trailing: all.isEmpty ? nil : "\(all.count)") {
            VStack(alignment: .leading, spacing: 6) {
                if all.isEmpty {
                    Label("All clear — no rain, heat, wind or earthquake alerts.",
                          systemImage: "checkmark.shield")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(all, id: \.self) { alert in
                        Text(alert)
                            .font(.system(size: 12))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.flame.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                if !quakes.quakes.isEmpty {
                    Divider()
                    Text("Earthquakes within 500 km (48 h)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(quakes.quakes.prefix(5)) { quake in
                        HStack {
                            Text("M\(String(format: "%.1f", quake.magnitude))")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(quake.magnitude >= 5 ? Theme.flame : Theme.accent)
                            Text(quake.place).font(.system(size: 11)).lineLimit(1)
                            Spacer()
                            Text(quake.date, format: .dateTime.day().month().hour().minute())
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }
}

// MARK: - Sun card (sunrise / sunset arc)

struct SunCard: View {
    @EnvironmentObject private var weather: WeatherStore

    var body: some View {
        Card(title: "Sun", systemImage: "sunrise") {
            VStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    SunArc(sunrise: weather.sunrise, sunset: weather.sunset, now: context.date)
                        .frame(height: 90)
                }
                HStack {
                    Label(weather.sunrise.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—",
                          systemImage: "sunrise.fill")
                    Spacer()
                    Label(weather.sunset.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—",
                          systemImage: "sunset.fill")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                if let length = dayLength {
                    Text("Daylight: \(length)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var dayLength: String? {
        guard let sunrise = weather.sunrise, let sunset = weather.sunset else { return nil }
        return formatHM(Int(sunset.timeIntervalSince(sunrise)))
    }
}

struct SunArc: View {
    let sunrise: Date?
    let sunset: Date?
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let center = CGPoint(x: width / 2, y: height - 4)
            let radius = min(width / 2 - 12, height - 14)

            ZStack {
                Path { path in
                    path.addArc(center: center, radius: radius,
                                startAngle: .degrees(180), endAngle: .degrees(0),
                                clockwise: false)
                }
                .stroke(Theme.cardStroke, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))

                Path { path in
                    path.move(to: CGPoint(x: 8, y: height - 4))
                    path.addLine(to: CGPoint(x: width - 8, y: height - 4))
                }
                .stroke(Theme.cardStroke, lineWidth: 1)

                if let t = progress {
                    let angle = Double.pi * (1 - t)
                    let x = center.x + radius * CGFloat(cos(angle))
                    let y = center.y - radius * CGFloat(sin(angle))
                    Circle()
                        .fill(Theme.flame.gradient)
                        .frame(width: 14, height: 14)
                        .shadow(color: Theme.flame.opacity(0.8), radius: 6)
                        .position(x: x, y: y)
                } else {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.accent)
                        .position(x: center.x, y: center.y - radius / 2)
                }
            }
        }
    }

    private var progress: Double? {
        guard let sunrise, let sunset, sunset > sunrise,
              now >= sunrise, now <= sunset else { return nil }
        return now.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)
    }
}
