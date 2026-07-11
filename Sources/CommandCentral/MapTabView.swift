import MapKit
import SwiftUI

struct MapTabView: View {
    @EnvironmentObject private var location: LocationStore
    @EnvironmentObject private var quakes: QuakeStore
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let lat = location.latitude, let lon = location.longitude {
            VStack(spacing: 10) {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)))) {
                    Marker(location.name ?? "Home",
                           systemImage: "house.fill",
                           coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                        .tint(.blue)
                    ForEach(quakes.quakes) { quake in
                        Marker("M\(String(format: "%.1f", quake.magnitude))",
                               systemImage: "dot.radiowaves.left.and.right",
                               coordinate: CLLocationCoordinate2D(latitude: quake.latitude,
                                                                  longitude: quake.longitude))
                            .tint(quake.magnitude >= 5 ? .red : .orange)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1))
                .id("\(lat),\(lon)")
                Text("🏠 \(location.name ?? "") — orange/red markers are earthquakes from the last 48 h within 500 km.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        } else {
            VStack(spacing: 12) {
                Text("🗺️").font(.system(size: 40))
                Text("Set your location in Settings to see your map.")
                    .foregroundStyle(.secondary)
                Button("Set Location in Settings") { state.showDashboardTab(.settings) }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
