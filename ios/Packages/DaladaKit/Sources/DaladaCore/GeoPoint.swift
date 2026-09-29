import Foundation

/// Точка на карте (WGS 84). Свой тип, чтобы доменный код не зависел от CoreLocation и MapLibre.
public struct GeoPoint: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Центр Алматы — стартовая точка карты.
    public static let almaty = GeoPoint(latitude: 43.238949, longitude: 76.889709)

    private static let earthRadiusM = 6_371_008.8

    /// Точка на расстоянии `distanceM` по азимуту `bearingDegrees` (сферическая модель Земли).
    public func destination(distanceM: Double, bearingDegrees: Double) -> GeoPoint {
        let angular = distanceM / Self.earthRadiusM
        let bearing = bearingDegrees * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        return GeoPoint(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    /// Расстояние до точки в метрах (гаверсинус).
    public func distance(to other: GeoPoint) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * Self.earthRadiusM * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Замкнутый многоугольник-круг радиуса `radiusM` вокруг точки (первая точка = последняя).
    public func circle(radiusM: Double, segments: Int = 64) -> [GeoPoint] {
        let count = max(segments, 8)
        return (0...count).map { index in
            destination(distanceM: radiusM, bearingDegrees: Double(index % count) * 360 / Double(count))
        }
    }
}

/// Прямоугольная область карты.
public struct GeoBoundingBox: Hashable, Sendable {
    public var minLongitude: Double
    public var minLatitude: Double
    public var maxLongitude: Double
    public var maxLatitude: Double

    public init(minLongitude: Double, minLatitude: Double, maxLongitude: Double, maxLatitude: Double) {
        self.minLongitude = minLongitude
        self.minLatitude = minLatitude
        self.maxLongitude = maxLongitude
        self.maxLatitude = maxLatitude
    }

    public var center: GeoPoint {
        GeoPoint(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
    }

    /// База принимает области не больше 10° по каждой оси — при сильном отдалении карты
    /// запрашиваем область вокруг центра.
    public func clamped(maxSpanDegrees: Double = 9.5) -> GeoBoundingBox {
        let halfLon = min(maxLongitude - minLongitude, maxSpanDegrees) / 2
        let halfLat = min(maxLatitude - minLatitude, maxSpanDegrees) / 2
        let c = center
        return GeoBoundingBox(
            minLongitude: c.longitude - halfLon,
            minLatitude: c.latitude - halfLat,
            maxLongitude: c.longitude + halfLon,
            maxLatitude: c.latitude + halfLat
        )
    }
}
