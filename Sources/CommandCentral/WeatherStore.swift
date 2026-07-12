import Foundation

struct RainHour: Identifiable {
    let date: Date
    let probability: Int
    var id: Date { date }
}

/// Weather via the free Open-Meteo API (no key needed).
final class WeatherStore: ObservableObject {
    @Published private(set) var temperature: Double?
    @Published private(set) var feelsLike: Double?
    @Published private(set) var humidity: Int?
    @Published private(set) var windSpeed: Double?
    @Published private(set) var code: Int?
    @Published private(set) var tempMax: Double?
    @Published private(set) var tempMin: Double?
    @Published private(set) var hourlyRain: [RainHour] = []
    @Published private(set) var sunrise: Date?
    @Published private(set) var sunset: Date?
    @Published private(set) var alerts: [String] = []
    @Published private(set) var lastUpdated: Date?

    private unowned let location: LocationStore
    private var timer: Timer?

    init(location: LocationStore) {
        self.location = location
        NotificationCenter.default.addObserver(forName: .locationChanged, object: nil,
                                               queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    func startMonitoring() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = 60
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    var emoji: String {
        switch code ?? -1 {
        case 0: return "☀️"
        case 1, 2: return "🌤️"
        case 3: return "☁️"
        case 45, 48: return "🌫️"
        case 51...67: return "🌧️"
        case 71...77: return "❄️"
        case 80...82: return "🌦️"
        case 85, 86: return "🌨️"
        case 95...99: return "⛈️"
        default: return "🌡️"
        }
    }

    var summary: String {
        switch code ?? -1 {
        case 0: return "Clear sky"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95...99: return "Thunderstorm"
        default: return "—"
        }
    }

    func refresh() {
        guard let lat = location.latitude, let lon = location.longitude else { return }
        let url = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m"
            + "&hourly=precipitation_probability&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset"
            + "&timezone=auto&forecast_days=2"
        fetchJSON(url, as: OMResponse.self) { [weak self] response in
            guard let self, let response else { return }
            self.apply(response)
        }
    }

    private func apply(_ response: OMResponse) {
        temperature = response.current?.temperature_2m
        feelsLike = response.current?.apparent_temperature
        humidity = response.current?.relative_humidity_2m
        windSpeed = response.current?.wind_speed_10m
        code = response.current?.weather_code
        tempMax = response.daily?.temperature_2m_max?.first
        tempMin = response.daily?.temperature_2m_min?.first

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        sunrise = response.daily?.sunrise?.first.flatMap { formatter.date(from: $0) }
        sunset = response.daily?.sunset?.first.flatMap { formatter.date(from: $0) }

        if let times = response.hourly?.time,
           let probs = response.hourly?.precipitation_probability {
            let now = Date()
            hourlyRain = zip(times, probs)
                .compactMap { time, prob -> RainHour? in
                    guard let date = formatter.date(from: time), date >= now else { return nil }
                    return RainHour(date: date, probability: prob)
                }
                .prefix(12)
                .map { $0 }
        }

        var newAlerts: [String] = []
        if let maxRain = hourlyRain.map(\.probability).max(), maxRain >= 60 {
            newAlerts.append("🌧️ Rain likely in the next 12 h (up to \(maxRain)% chance) — carry an umbrella.")
        }
        if let temp = temperature, temp >= 40 {
            newAlerts.append("🥵 Extreme heat: \(Int(temp))°C right now — stay hydrated.")
        }
        if let wind = windSpeed, wind >= 50 {
            newAlerts.append("💨 Strong winds: \(Int(wind)) km/h.")
        }
        if let code, (95...99).contains(code) {
            newAlerts.append("⛈️ Thunderstorm conditions near you.")
        }
        for alert in newAlerts where !alerts.contains(alert) {
            NotificationManager.shared.notify(title: "Weather alert", body: alert)
        }
        alerts = newAlerts
        lastUpdated = Date()
    }
}

private struct OMResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double?
        let relative_humidity_2m: Int?
        let apparent_temperature: Double?
        let weather_code: Int?
        let wind_speed_10m: Double?
    }
    struct Hourly: Decodable {
        let time: [String]?
        let precipitation_probability: [Int]?
    }
    struct Daily: Decodable {
        let temperature_2m_max: [Double]?
        let temperature_2m_min: [Double]?
        let sunrise: [String]?
        let sunset: [String]?
    }
    let current: Current?
    let hourly: Hourly?
    let daily: Daily?
}
