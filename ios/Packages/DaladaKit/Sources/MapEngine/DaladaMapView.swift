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

/// Зона правил на карте: многоугольники (внешний контур и отверстия) и состояние запрета.
public struct MapRuleArea: Hashable, Sendable, Identifiable {
    public enum State: String, Hashable, Sendable {
        /// Запрет действует.
        case active
        /// Скоро начнётся.
        case soon
        /// Запрета сейчас нет.
        case none
    }

    public let id: String
    public let polygons: [[[GeoPoint]]]
    public let state: State

    public init(id: String, polygons: [[[GeoPoint]]], state: State) {
        self.id = id
        self.polygons = polygons
        self.state = state
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
    /// Отрезки трека: своя поездка — один, чужая — видимые части без скрытых участков.
    let trackSegments: [[GeoPoint]]
    /// Маршрут, по которому человек идёт (следование), — широкой полупрозрачной линией под треком.
    let routeSegments: [[GeoPoint]]
    let cameraMode: MapCameraMode
    /// Зоны правил (запреты) — под местами и треком.
    let ruleAreas: [MapRuleArea]
    let onRegionChange: @MainActor (GeoBoundingBox) -> Void
    let onPlaceTap: @MainActor (UUID) -> Void
    let onRuleAreaTap: @MainActor (String) -> Void
    let onLongPress: @MainActor (GeoPoint) -> Void

    public init(
        styleURL: URL,
        initialCenter: GeoPoint = .almaty,
        initialZoom: Double = 8,
        showsUserLocation: Bool = true,
        places: [MapPlace] = [],
        draftPin: GeoPoint? = nil,
        trackSegments: [[GeoPoint]] = [],
        routeSegments: [[GeoPoint]] = [],
        cameraMode: MapCameraMode = .free,
        ruleAreas: [MapRuleArea] = [],
        onRegionChange: @escaping @MainActor (GeoBoundingBox) -> Void = { _ in },
        onPlaceTap: @escaping @MainActor (UUID) -> Void = { _ in },
        onRuleAreaTap: @escaping @MainActor (String) -> Void = { _ in },
        onLongPress: @escaping @MainActor (GeoPoint) -> Void = { _ in }
    ) {
        self.styleURL = styleURL
        self.initialCenter = initialCenter
        self.initialZoom = initialZoom
        self.showsUserLocation = showsUserLocation
        self.places = places
        self.draftPin = draftPin
        self.trackSegments = trackSegments
        self.routeSegments = routeSegments
        self.cameraMode = cameraMode
        self.ruleAreas = ruleAreas
        self.onRegionChange = onRegionChange
        self.onPlaceTap = onPlaceTap
        self.onRuleAreaTap = onRuleAreaTap
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
        private var routeSource: MLNShapeSource?
        private var renderedRoute: [[GeoPoint]]?
        private var ruleSource: MLNShapeSource?
        private var renderedRuleAreas: [MapRuleArea]?
        private var renderedPlaces: [MapPlace]?
        private var renderedDraft: GeoPoint?
        private var renderedTrack: [[GeoPoint]]?
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
            static let routeSource = "dalada-route"
            static let routeLine = "dalada-route-line"
            static let ruleSource = "dalada-rules"
            static let ruleFill = "dalada-rules-fill"
            static let ruleLine = "dalada-rules-line"
        }

        /// Обновляет источник мест, если данные изменились. До загрузки стиля — ничего не делает:
        /// отрисуем в `didFinishLoading`.
        func render() {
            if let ruleSource, parent.ruleAreas != renderedRuleAreas {
                renderedRuleAreas = parent.ruleAreas
                ruleSource.shape = MLNShapeCollectionFeature(shapes: Self.ruleFeatures(parent.ruleAreas))
            }
            if let routeSource, parent.routeSegments != renderedRoute {
                renderedRoute = parent.routeSegments
                routeSource.shape = Self.trackShape(parent.routeSegments)
            }
            if let trackSource, parent.trackSegments != renderedTrack {
                renderedTrack = parent.trackSegments
                trackSource.shape = Self.trackShape(parent.trackSegments)
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
                let points = parent.trackSegments.flatMap { $0 }
                guard points.count >= 2 else { return }
                let latitudes = points.map(\.latitude)
                let longitudes = points.map(\.longitude)
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

        static func trackShape(_ segments: [[GeoPoint]]) -> MLNShape? {
            let lines: [MLNPolylineFeature] = segments.compactMap { segment in
                guard segment.count >= 2 else { return nil }
                var coordinates = segment.map(\.clCoordinate)
                return MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
            }
            switch lines.count {
            case 0: return nil
            case 1: return lines[0]
            default: return MLNMultiPolylineFeature(polylines: lines)
            }
        }

        static func ruleFeatures(_ areas: [MapRuleArea]) -> [MLNShape & MLNFeature] {
            areas.compactMap { area -> (MLNShape & MLNFeature)? in
                let polygons: [MLNPolygon] = area.polygons.compactMap { rings in
                    guard var outer = rings.first?.map(\.clCoordinate), outer.count >= 3 else { return nil }
                    let holes: [MLNPolygon] = rings.dropFirst().compactMap { ring in
                        var coordinates = ring.map(\.clCoordinate)
                        guard coordinates.count >= 3 else { return nil }
                        return MLNPolygon(coordinates: &coordinates, count: UInt(coordinates.count))
                    }
                    return MLNPolygon(coordinates: &outer, count: UInt(outer.count), interiorPolygons: holes)
                }
                guard !polygons.isEmpty else { return nil }
                let feature = MLNMultiPolygonFeature(polygons: polygons)
                feature.attributes = ["id": area.id, "state": area.state.rawValue]
                return feature
            }
        }

        func installLayers(in style: MLNStyle) {
            // Зоны правил — ниже трека и мест.
            let ruleSource = MLNShapeSource(identifier: Layer.ruleSource, shape: nil, options: nil)
            style.addSource(ruleSource)
            let stateColor = NSExpression(
                format: "TERNARY(state == 'active', %@, TERNARY(state == 'soon', %@, %@))",
                UIColor.systemRed,
                UIColor.systemOrange,
                UIColor.systemGray
            )
            let ruleFill = MLNFillStyleLayer(identifier: Layer.ruleFill, source: ruleSource)
            ruleFill.fillColor = stateColor
            ruleFill.fillOpacity = NSExpression(format: "TERNARY(state == 'active', 0.25, TERNARY(state == 'soon', 0.2, 0.08))")
            style.addLayer(ruleFill)
            let ruleLine = MLNLineStyleLayer(identifier: Layer.ruleLine, source: ruleSource)
            ruleLine.lineColor = stateColor
            ruleLine.lineWidth = NSExpression(forConstantValue: 1.5)
            ruleLine.lineOpacity = NSExpression(forConstantValue: 0.7)
            style.addLayer(ruleLine)
            self.ruleSource = ruleSource
            renderedRuleAreas = nil

            // Маршрут для следования — под треком.
            let routeSource = MLNShapeSource(identifier: Layer.routeSource, shape: nil, options: nil)
            style.addSource(routeSource)
            let routeLine = MLNLineStyleLayer(identifier: Layer.routeLine, source: routeSource)
            routeLine.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
            routeLine.lineWidth = NSExpression(forConstantValue: 7)
            routeLine.lineOpacity = NSExpression(forConstantValue: 0.55)
            routeLine.lineCap = NSExpression(forConstantValue: "round")
            routeLine.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(routeLine)
            self.routeSource = routeSource
            renderedRoute = nil

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
            if let idString = hit?.attribute(forKey: "id") as? String, let id = UUID(uuidString: idString) {
                parent.onPlaceTap(id)
                return
            }
            // Мимо мест — зона правил под пальцем.
            let ruleHits = mapView.visibleFeatures(at: point, styleLayerIdentifiers: [Layer.ruleFill])
            if let zoneID = ruleHits.first?.attribute(forKey: "id") as? String {
                parent.onRuleAreaTap(zoneID)
            }
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
