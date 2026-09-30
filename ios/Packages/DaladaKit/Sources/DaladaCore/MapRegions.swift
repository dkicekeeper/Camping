import Foundation

/// Прямоугольник на карте: юго-западный и северо-восточный углы.
public struct GeoBounds: Hashable, Sendable {
    public var southWest: GeoPoint
    public var northEast: GeoPoint

    public init(south: Double, west: Double, north: Double, east: Double) {
        southWest = GeoPoint(latitude: south, longitude: west)
        northEast = GeoPoint(latitude: north, longitude: east)
    }

    public func contains(_ other: GeoBounds) -> Bool {
        other.southWest.latitude >= southWest.latitude && other.southWest.longitude >= southWest.longitude
            && other.northEast.latitude <= northEast.latitude && other.northEast.longitude <= northEast.longitude
    }

    /// Сколько тайлов (256 px, схема XYZ) покрывают прямоугольник на масштабах `zooms`.
    public func tileCount(zooms: ClosedRange<Int>) -> Int {
        zooms.reduce(0) { total, zoom in
            let (x0, y1) = Self.tile(southWest, zoom: zoom)
            let (x1, y0) = Self.tile(northEast, zoom: zoom)
            return total + (x1 - x0 + 1) * (y1 - y0 + 1)
        }
    }

    static func tile(_ point: GeoPoint, zoom: Int) -> (x: Int, y: Int) {
        let n = Double(1 << zoom)
        let lat = point.latitude * .pi / 180
        let x = Int((point.longitude + 180) / 360 * n)
        let y = Int((1 - asinh(tan(lat)) / .pi) / 2 * n)
        return (min(x, Int(n) - 1), min(y, Int(n) - 1))
    }
}

/// Район, который можно скачать заранее и открывать без сети («Карты без сети»).
public struct MapRegion: Identifiable, Hashable, Sendable {
    public let id: String
    public let bounds: GeoBounds
    /// До какого масштаба скачивать: подробно (14) — для небольших районов, для больших — 13
    /// (крупнее карта растягивает тайлы 13-го масштаба).
    public let maxZoom: Int

    /// С какого масштаба скачивать: мельче район целиком виден и так.
    public static let minZoom = 6

    public var titleKey: String { "offlineMaps.region.\(id)" }
    public var zooms: ClosedRange<Int> { Self.minZoom...maxZoom }
    public var tileCount: Int { bounds.tileCount(zooms: zooms) }

    /// Примерный размер: в среднем ~16 КБ на тайл за городом (по сборке тайлов региона).
    public var estimatedBytes: Int64 { Int64(tileCount) * 16 * 1024 }
}

public enum MapRegions {
    /// Всё, что есть на своих тайлах: Алматинская область, Жетісу и Алматы с запасом
    /// (map/config.json → bounds).
    public static let coverage = GeoBounds(south: 42.15, west: 73.6, north: 47.35, east: 82.7)

    public static let all: [MapRegion] = [
        MapRegion(id: "almaty_mountains", bounds: GeoBounds(south: 42.95, west: 76.55, north: 43.45, east: 77.75), maxZoom: 14),
        MapRegion(id: "kapshagay", bounds: GeoBounds(south: 43.55, west: 76.95, north: 44.10, east: 78.15), maxZoom: 14),
        MapRegion(id: "ile", bounds: GeoBounds(south: 43.80, west: 76.10, north: 44.90, east: 77.20), maxZoom: 13),
        MapRegion(id: "charyn_kolsay", bounds: GeoBounds(south: 42.85, west: 78.00, north: 43.60, east: 79.40), maxZoom: 13),
        MapRegion(id: "ile_delta_balkhash", bounds: GeoBounds(south: 44.70, west: 74.40, north: 46.40, east: 77.60), maxZoom: 12),
        MapRegion(id: "taldykorgan", bounds: GeoBounds(south: 44.75, west: 77.80, north: 45.45, east: 79.00), maxZoom: 13),
        MapRegion(id: "alakol", bounds: GeoBounds(south: 45.60, west: 80.50, north: 46.75, east: 82.30), maxZoom: 13),
    ]

    public static func region(id: String) -> MapRegion? {
        all.first { $0.id == id }
    }
}
