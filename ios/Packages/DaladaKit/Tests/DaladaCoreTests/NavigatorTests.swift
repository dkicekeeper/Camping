import Foundation
import Testing
@testable import DaladaCore

@Suite("Navigator")
struct NavigatorTests {
    let point = GeoPoint(latitude: 43.828654, longitude: 77.608795)

    @Test func appLinksPutCoordinatesInTheirOrder() {
        #expect(Navigator.twoGIS.appURL(to: point)?.absoluteString
            == "dgis://2gis.ru/routeSearch/rsType/car/to/77.608795,43.828654")
        #expect(Navigator.yandexNavigator.appURL(to: point)?.absoluteString
            == "yandexnavi://build_route_on_map?lat_to=43.828654&lon_to=77.608795")
        #expect(Navigator.google.appURL(to: point)?.absoluteString
            == "comgooglemaps://?daddr=43.828654,77.608795&directionsmode=driving")
        #expect(Navigator.apple.appURL(to: point)?.host == "maps.apple.com")
    }

    @Test func websiteWhenTheAppIsMissing() {
        #expect(Navigator.twoGIS.url(to: point, installed: false)?.absoluteString
            == "https://2gis.kz/routeSearch/rsType/car/to/77.608795,43.828654")
        #expect(Navigator.google.url(to: point, installed: false)?.host == "www.google.com")
        #expect(Navigator.apple.url(to: point, installed: false)?.host == "maps.apple.com")
        #expect(Navigator.yandexNavigator.webURL(to: point) == nil)
    }

    @Test func installedNavigatorsComeFirst() {
        let choices = Navigator.choices { $0 == "yandexnavi" || $0 == "comgooglemaps" }
        #expect(choices == [.yandexNavigator, .google, .twoGIS, .yandexMaps, .apple])
        // Без установленных приложений Яндекс Навигатора нет — у него нет сайта.
        #expect(Navigator.choices { _ in false } == [.twoGIS, .yandexMaps, .google, .apple])
    }

    @Test func coordinatesUseADotInAnyLocale() {
        #expect(Navigator.coordinate(43.5) == "43.500000")
        #expect(Navigator.coordinate(-0.1234567) == "-0.123457")
    }
}
