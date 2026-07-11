import Foundation

/// Tiny JSON fetch helper used by weather/quake/geocoding stores.
func fetchJSON<T: Decodable>(_ urlString: String, as type: T.Type,
                             completion: @escaping (T?) -> Void) {
    guard let url = URL(string: urlString) else {
        completion(nil)
        return
    }
    URLSession.shared.dataTask(with: url) { data, _, _ in
        let decoded = data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
        DispatchQueue.main.async { completion(decoded) }
    }.resume()
}

struct GeoResult: Decodable, Identifiable {
    let id: Int
    let name: String
    let country: String?
    let admin1: String?
    let latitude: Double
    let longitude: Double

    var display: String {
        [name, admin1, country].compactMap { $0 }.joined(separator: ", ")
    }
}

/// The home location everything weather/quake/sun related is based on.
/// Set manually by city search (Open-Meteo geocoding) — no permissions needed.
final class LocationStore: ObservableObject {
    @Published private(set) var name: String?
    @Published private(set) var latitude: Double?
    @Published private(set) var longitude: Double?
    @Published var searchResults: [GeoResult] = []

    var isSet: Bool { latitude != nil && longitude != nil }

    init() {
        let defaults = UserDefaults.standard
        name = defaults.string(forKey: "locationName")
        if defaults.object(forKey: "locationLat") != nil {
            latitude = defaults.double(forKey: "locationLat")
            longitude = defaults.double(forKey: "locationLon")
        }
    }

    func set(_ result: GeoResult) {
        name = result.display
        latitude = result.latitude
        longitude = result.longitude
        let defaults = UserDefaults.standard
        defaults.set(name, forKey: "locationName")
        defaults.set(result.latitude, forKey: "locationLat")
        defaults.set(result.longitude, forKey: "locationLon")
        searchResults = []
        NotificationCenter.default.post(name: .locationChanged, object: nil)
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        struct Response: Decodable { let results: [GeoResult]? }
        fetchJSON("https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=6",
                  as: Response.self) { [weak self] response in
            self?.searchResults = response?.results ?? []
        }
    }
}

extension Notification.Name {
    static let locationChanged = Notification.Name("locationChanged")
    static let alarmFired = Notification.Name("alarmFired")
}
