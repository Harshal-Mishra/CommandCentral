import Foundation

struct Quake: Identifiable {
    let id: String
    let magnitude: Double
    let place: String
    let date: Date
    let latitude: Double
    let longitude: Double
}

/// Recent nearby earthquakes from the USGS public feed (last 48 h, M3+,
/// within 500 km of your set location).
final class QuakeStore: ObservableObject {
    @Published private(set) var quakes: [Quake] = []
    @Published private(set) var lastUpdated: Date?

    private unowned let location: LocationStore
    private var timer: Timer?
    private var notifiedQuakeIDs: [String] = []

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

    func refresh() {
        guard let lat = location.latitude, let lon = location.longitude else { return }
        let start = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-48 * 3600))
        let url = "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson"
            + "&latitude=\(lat)&longitude=\(lon)&maxradiuskm=500&minmagnitude=3&starttime=\(start)"
        fetchJSON(url, as: USGSResponse.self) { [weak self] response in
            guard let self else { return }
            self.quakes = (response?.features ?? []).compactMap { feature in
                guard let mag = feature.properties.mag,
                      let time = feature.properties.time,
                      feature.geometry.coordinates.count >= 2 else { return nil }
                return Quake(id: feature.id,
                             magnitude: mag,
                             place: feature.properties.place ?? "nearby",
                             date: Date(timeIntervalSince1970: time / 1000),
                             latitude: feature.geometry.coordinates[1],
                             longitude: feature.geometry.coordinates[0])
            }
            .sorted { $0.date > $1.date }
            let knownIDs = Set(self.notifiedQuakeIDs)
            for quake in self.quakes where quake.magnitude >= 4.5 && !knownIDs.contains(quake.id) {
                NotificationManager.shared.notify(
                    title: "🌍 Earthquake nearby",
                    body: "M\(String(format: "%.1f", quake.magnitude)) \(quake.place)")
                self.notifiedQuakeIDs.append(quake.id)
            }
            if self.notifiedQuakeIDs.count > 100 {
                self.notifiedQuakeIDs.removeFirst(self.notifiedQuakeIDs.count - 100)
            }
            self.lastUpdated = Date()
        }
    }

    var alerts: [String] {
        quakes.filter { $0.magnitude >= 4 }.prefix(3).map {
            "🌍 M\(String(format: "%.1f", $0.magnitude)) earthquake \($0.place)"
        }
    }
}

private struct USGSResponse: Decodable {
    struct Feature: Decodable {
        struct Props: Decodable {
            let mag: Double?
            let place: String?
            let time: Double?
        }
        struct Geometry: Decodable {
            let coordinates: [Double]
        }
        let id: String
        let properties: Props
        let geometry: Geometry
    }
    let features: [Feature]
}
