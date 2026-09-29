import CoreLocation
import DaladaCore
import MapLibre
import SwiftUI

/// Карта Dalada — SwiftUI-обёртка над `MLNMapView`.
///
/// Пока это базовая карта со стилем и позицией пользователя. Слои мест, правил и треков,
/// офлайн-пакеты — следующими этапами (docs/03-architecture/03-maps-geo.md).
public struct DaladaMapView: UIViewRepresentable {
    private let styleURL: URL
    private let initialCenter: GeoPoint
    private let initialZoom: Double
    private let showsUserLocation: Bool

    public init(
        styleURL: URL,
        initialCenter: GeoPoint = .almaty,
        initialZoom: Double = 8,
        showsUserLocation: Bool = true
    ) {
        self.styleURL = styleURL
        self.initialCenter = initialCenter
        self.initialZoom = initialZoom
        self.showsUserLocation = showsUserLocation
    }

    public func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: initialCenter.latitude, longitude: initialCenter.longitude),
            zoomLevel: initialZoom,
            animated: false
        )
        // Запрос разрешения на геолокацию MapLibre делает сам; текст — в InfoPlist.xcstrings.
        mapView.showsUserLocation = showsUserLocation
        return mapView
    }

    public func updateUIView(_ mapView: MLNMapView, context: Context) {}
}
