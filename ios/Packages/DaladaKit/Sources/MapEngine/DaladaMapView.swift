import CoreLocation
import DaladaCore
import MapLibre
import SwiftUI
import UIKit

/// Место для отрисовки на карте.
public struct MapPlace: Hashable, Sendable, Identifiable {
    public let id: UUID
    /// Показанная точка (у чужих приблизительных мест — смещённый центр круга).
    public let coordinate: GeoPoint
    public let isOwn: Bool
    /// Радиус круга для приблизительного места; `nil` — точное место.
    public let approximateRadiusM: Int?

    public init(id: UUID, coordinate: GeoPoint, isOwn: Bool, approximateRadiusM: Int?) {
        self.id = id
        self.coordinate = coordinate
        self.isOwn = isOwn
        self.approximateRadiusM = approximateRadiusM
    }
}

/// Как ведёт себя камера карты.
public enum MapCameraMode: Hashable, Sendable {
    /// Пользователь двигает карту сам.
    case free
    /// Карта следует за пользователем (запись поездки).
    case followUser
    /// Показать трек целиком (страница поездки).
    case fitTrack
}

/// Карта Dalada — SwiftUI-обёртка над `MLNMapView`.
///
/// Места рисуются слоями стиля из одного GeoJSON-источника: круги приблизительных мест,
/// точки мест и метка нового места; трек — линией из отдельного источника. Фичи не импортируют
/// MapLibre — только этот модуль.
public struct DaladaMapView: UIViewRepresentable {
    let styleURL: URL
    let initialCenter: GeoPoint
    let initialZoom: Double
    let showsUserLocation: Bool
    let places: [MapPlace]
    let draftPin: GeoPoint?
    let track: [GeoPoint]
    let cameraMode: MapCameraMode
    let onRegionChange: @MainActor (GeoBoundingBox) -> Void
    let onPlaceTap: @MainActor (UUID) -> Void
    let onLongPress: @MainActor (GeoPoint) -> Void

    public init(
        styleURL: URL,
        initialCenter: GeoPoint = .almaty,
        initialZoom: Double = 8,
        showsUserLocation: Bool = true,
        places: [MapPlace] = [],
        draftPin: GeoPoint? = nil,
        track: [GeoPoint] = [],
        cameraMode: MapCameraMode = .free,
        onRegionChange: @escaping @MainActor (GeoBoundingBox) -> Void = { _ in },
        onPlaceTap: @escaping @MainActor (UUID) -> Void = { _ in },
        onLongPress: @escaping @MainActor (GeoPoint) -> Void = { _ in }
    ) {
        self.styleURL = styleURL
        self.initialCenter = initialCenter
        self.initialZoom = initialZoom
        self.showsUserLocation = showsUserLocation
        self.places = places
        self.draftPin = draftPin
        self.track = track
        self.cameraMode = cameraMode
        self.onRegionChange = onRegionChange
        self.onPlaceTap = onPlaceTap
        self.onLongPress = onLongPress
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
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
        mapView.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        // Одиночный тап срабатывает, только если это не двойной тап (зум).
        for recognizer in mapView.gestureRecognizers ?? [] where recognizer is UITapGestureRecognizer {
            tap.require(toFail: recognizer)
        }
        mapView.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        mapView.addGestureRecognizer(longPress)
        context.coordinator.mapView = mapView
        return mapView
    }

    public func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render()
        context.coordinator.applyCamera()
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject {
        var parent: DaladaMapView
        weak var mapView: MLNMapView?
        private var source: MLNShapeSource?
        private var trackSource: MLNShapeSource?
        private var renderedPlaces: [MapPlace]?
        private var renderedDraft: GeoPoint?
        private var renderedTrack: [GeoPoint]?
        private var appliedCamera: MapCameraMode?
        private var isStyleLoaded = false

        init(parent: DaladaMapView) {
            self.parent = parent
        }

        enum Layer {
            static let source = "dalada-places"
            static let areas = "dalada-place-areas"
            static let points = "dalada-place-points"
            static let draft = "dalada-draft-pin"
            static let trackSource = "dalada-track"
            static let trackLine = "dalada-track-line"
        }

        /// Обновляет источник мест, если данные изменились. До загрузки стиля — ничего не делает:
        /// отрисуем в `didFinishLoading`.
        func render() {
            if let trackSource, parent.track != renderedTrack {
                renderedTrack = parent.track
                trackSource.shape = Self.trackShape(parent.track)
            }
            guard let source else { return }
            guard parent.places != renderedPlaces || parent.draftPin != renderedDraft else { return }
            renderedPlaces = parent.places
            renderedDraft = parent.draftPin
            source.shape = MLNShapeCollectionFeature(shapes: Self.features(places: parent.places, draft: parent.draftPin))
        }

        /// Режим камеры применяется один раз при смене: дальше пользователь может двигать карту.
        func applyCamera() {
            guard isStyleLoaded, let mapView, parent.cameraMode != appliedCamera else { return }
            switch parent.cameraMode {
            case .free:
                mapView.userTrackingMode = .none
            case .followUser:
                mapView.showsUserLocation = true
                mapView.setUserTrackingMode(.follow, animated: true, completionHandler: nil)
            case .fitTrack:
                guard parent.track.count >= 2 else { return }
                let latitudes = parent.track.map(\.latitude)
                let longitudes = parent.track.map(\.longitude)
                let bounds = MLNCoordinateBounds(
                    sw: CLLocationCoordinate2D(latitude: latitudes.min()!, longitude: longitudes.min()!),
                    ne: CLLocationCoordinate2D(latitude: latitudes.max()!, longitude: longitudes.max()!)
                )
                mapView.setVisibleCoordinateBounds(
                    bounds,
                    edgePadding: UIEdgeInsets(top: 40, left: 32, bottom: 40, right: 32),
                    animated: false,
                    completionHandler: nil
                )
            }
            appliedCamera = parent.cameraMode
        }

        static func trackShape(_ track: [GeoPoint]) -> MLNShape? {
            guard track.count >= 2 else { return nil }
            var coordinates = track.map(\.clCoordinate)
            return MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
        }

        func installLayers(in style: MLNStyle) {
            // Трек — под точками мест.
            let trackSource = MLNShapeSource(identifier: Layer.trackSource, shape: nil, options: nil)
            style.addSource(trackSource)
            let trackLine = MLNLineStyleLayer(identifier: Layer.trackLine, source: trackSource)
            trackLine.lineColor = NSExpression(forConstantValue: UIColor.systemOrange)
            trackLine.lineWidth = NSExpression(forConstantValue: 4)
            trackLine.lineCap = NSExpression(forConstantValue: "round")
            trackLine.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(trackLine)
            self.trackSource = trackSource
            renderedTrack = nil

            let source = MLNShapeSource(identifier: Layer.source, shape: nil, options: nil)
            style.addSource(source)

            let areas = MLNFillStyleLayer(identifier: Layer.areas, source: source)
            areas.predicate = NSPredicate(format: "kind == 'area'")
            areas.fillColor = NSExpression(forConstantValue: UIColor.systemIndigo)
            areas.fillOpacity = NSExpression(forConstantValue: 0.18)
            areas.fillOutlineColor = NSExpression(forConstantValue: UIColor.systemIndigo)
            style.addLayer(areas)

            let points = MLNCircleStyleLayer(identifier: Layer.points, source: source)
            points.predicate = NSPredicate(format: "kind == 'place'")
            points.circleRadius = NSExpression(forConstantValue: 7)
            points.circleColor = NSExpression(
                format: "TERNARY(own == YES, %@, %@)",
                UIColor.systemOrange,
                UIColor.systemIndigo
            )
            points.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            points.circleStrokeWidth = NSExpression(forConstantValue: 2)
            style.addLayer(points)

            let draft = MLNCircleStyleLayer(identifier: Layer.draft, source: source)
            draft.predicate = NSPredicate(format: "kind == 'draft'")
            draft.circleRadius = NSExpression(forConstantValue: 9)
            draft.circleColor = NSExpression(forConstantValue: UIColor.systemRed)
            draft.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            draft.circleStrokeWidth = NSExpression(forConstantValue: 3)
            style.addLayer(draft)

            self.source = source
            renderedPlaces = nil
            render()
        }

        static func features(places: [MapPlace], draft: GeoPoint?) -> [MLNShape & MLNFeature] {
            var features: [MLNShape & MLNFeature] = []
            for place in places {
                if let radius = place.approximateRadiusM {
                    var ring = place.coordinate.circle(radiusM: Double(radius)).map(\.clCoordinate)
                    let area = MLNPolygonFeature(coordinates: &ring, count: UInt(ring.count))
                    area.attributes = ["kind": "area", "id": place.id.uuidString]
                    features.append(area)
                }
                let point = MLNPointFeature()
                point.coordinate = place.coordinate.clCoordinate
                point.attributes = ["kind": "place", "id": place.id.uuidString, "own": place.isOwn]
                features.append(point)
            }
            if let draft {
                let pin = MLNPointFeature()
                pin.coordinate = draft.clCoordinate
                pin.attributes = ["kind": "draft"]
                features.append(pin)
            }
            return features
        }

        // MARK: Жесты

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let mapView = recognizer.view as? MLNMapView else { return }
            let point = recognizer.location(in: mapView)
            let hitArea = CGRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32)
            let hits = mapView.visibleFeatures(in: hitArea, styleLayerIdentifiers: [Layer.points, Layer.areas])
            // Точка важнее круга: если попали в обе, открываем точку.
            let hit = hits.first { ($0.attribute(forKey: "kind") as? String) == "place" } ?? hits.first
            guard let idString = hit?.attribute(forKey: "id") as? String, let id = UUID(uuidString: idString) else { return }
            parent.onPlaceTap(id)
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let mapView = recognizer.view as? MLNMapView else { return }
            let coordinate = mapView.convert(recognizer.location(in: mapView), toCoordinateFrom: mapView)
            parent.onLongPress(GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }

        func reportRegion(of mapView: MLNMapView) {
            let bounds = mapView.visibleCoordinateBounds
            parent.onRegionChange(
                GeoBoundingBox(
                    minLongitude: bounds.sw.longitude,
                    minLatitude: bounds.sw.latitude,
                    maxLongitude: bounds.ne.longitude,
                    maxLatitude: bounds.ne.latitude
                )
            )
        }
    }
}

// Протокол MapLibre не помечен @MainActor, но вызывается на главном потоке.
extension DaladaMapView.Coordinator: @preconcurrency MLNMapViewDelegate {
    public func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        installLayers(in: style)
        isStyleLoaded = true
        applyCamera()
        reportRegion(of: mapView)
    }

    public func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
        reportRegion(of: mapView)
    }
}

extension GeoPoint {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
