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
}
