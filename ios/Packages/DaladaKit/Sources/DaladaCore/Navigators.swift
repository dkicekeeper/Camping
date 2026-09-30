import Foundation

/// Навигатор для «Маршрута» до места: приложение (если установлено) или сайт.
public enum Navigator: String, CaseIterable, Identifiable, Sendable {
    case twoGIS = "2gis"
    case yandexNavigator = "yandex_navigator"
    case yandexMaps = "yandex_maps"
    case google
    case apple

    public var id: String { rawValue }
    public var titleKey: String { "navigator.\(rawValue)" }

    /// Схема приложения — для проверки, установлено ли оно (`LSApplicationQueriesSchemes` в
    /// Info.plist). Apple Карты есть всегда.
    public var appScheme: String? {
        switch self {
        case .twoGIS: "dgis"
        case .yandexNavigator: "yandexnavi"
        case .yandexMaps: "yandexmaps"
        case .google: "comgooglemaps"
        case .apple: nil
        }
    }

    /// Маршрут на машине до точки в приложении навигатора.
    public func appURL(to point: GeoPoint) -> URL? {
        let lat = Self.coordinate(point.latitude)
        let lon = Self.coordinate(point.longitude)
        let string = switch self {
        case .twoGIS: "dgis://2gis.ru/routeSearch/rsType/car/to/\(lon),\(lat)"
        case .yandexNavigator: "yandexnavi://build_route_on_map?lat_to=\(lat)&lon_to=\(lon)"
        case .yandexMaps: "yandexmaps://maps.yandex.ru/?rtext=~\(lat),\(lon)&rtt=auto"
        case .google: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving"
        case .apple: "https://maps.apple.com/?daddr=\(lat),\(lon)&dirflg=d"
        }
        return URL(string: string)
    }

    /// Тот же маршрут на сайте — если приложения нет. У Яндекс Навигатора сайта нет.
    public func webURL(to point: GeoPoint) -> URL? {
        let lat = Self.coordinate(point.latitude)
        let lon = Self.coordinate(point.longitude)
        let string: String? = switch self {
        case .twoGIS: "https://2gis.kz/routeSearch/rsType/car/to/\(lon),\(lat)"
        case .yandexNavigator: nil
        case .yandexMaps: "https://yandex.kz/maps/?rtext=~\(lat),\(lon)&rtt=auto"
        case .google: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lon)&travelmode=driving"
        case .apple: "https://maps.apple.com/?daddr=\(lat),\(lon)&dirflg=d"
        }
        return string.flatMap(URL.init(string:))
    }

    /// Какие навигаторы предложить: установленные — первыми, потом сайты; Яндекс Навигатор — только
    /// если установлен. `isInstalled` — проверка схемы на телефоне.
    public static func choices(isInstalled: (String) -> Bool) -> [Navigator] {
        let installed = allCases.filter { navigator in
            navigator.appScheme.map(isInstalled) ?? false
        }
        let web = allCases.filter { navigator in
            !installed.contains(navigator) && navigator.webURL(to: .almaty) != nil
        }
        return installed + web
    }

    /// Адрес для открытия: приложение, если установлено, иначе сайт.
    public func url(to point: GeoPoint, installed: Bool) -> URL? {
        installed || appScheme == nil ? appURL(to: point) : webURL(to: point)
    }

    /// Шесть знаков после запятой (~10 см) и точка как разделитель при любом языке телефона.
    static func coordinate(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
