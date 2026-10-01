import Foundation
import Testing
@testable import DaladaCore

@Suite("PlaceDiscovery")
struct PlaceDiscoveryTests {
    /// Ответ `places_discover` в том виде, как его отдаёт PostgREST.
    static let json = """
    {
      "nearby": [{
        "id": "1be00922-6079-43c5-a5f5-ed907bf4398d", "type": "tackle_shop", "name": "Seledkin",
        "lon": 76.908873, "lat": 43.245197, "approximate": false, "radius_m": 0,
        "visibility": "public", "is_own": false, "is_editorial": true, "distance_m": 3382,
        "rating_avg": null, "reviews_count": 0, "reports_30d": 0, "last_report_at": null,
        "photo_path": null, "friends": [], "saved": false
      }],
      "popular": [],
      "friends": [{
        "id": "aaaaaaaa-0000-0000-0000-000000000001", "type": "water_body", "name": "Озеро",
        "lon": 77.0, "lat": 43.9, "approximate": true, "radius_m": 1000,
        "visibility": "public", "is_own": false, "is_editorial": false, "distance_m": null,
        "rating_avg": 4.5, "reviews_count": 2, "reports_30d": 3,
        "last_report_at": "2026-10-01T05:12:33.123456+00:00",
        "photo_path": "22222222-2222-2222-2222-222222222222/eeeeeeee-0000-0000-0000-000000000001_thumb.jpg",
        "friends": [{"id": "22222222-2222-2222-2222-222222222222", "username": "friend_f",
                     "display_name": null, "avatar_path": null}],
        "saved": true
      }],
      "fresh": [],
      "new": [],
      "recommended": [{
        "id": "bbbbbbbb-0000-0000-0000-000000000001", "slug": "springs",
        "title": {"ru": "Родники", "kk": "Бұлақтар", "en": "Springs"},
        "places": []
      }]
    }
    """

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let format = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            return try format.parse(text)
        }
        return decoder
    }

    @Test func decodesServerResponse() throws {
        let discovery = try Self.decoder().decode(PlaceDiscovery.self, from: Data(Self.json.utf8))
        #expect(discovery.nearby.first?.name == "Seledkin")
        #expect(discovery.nearby.first?.isEditorial == true)
        #expect(discovery.nearby.first?.distanceM == 3382)
        #expect(discovery.nearby.first?.ratingAvg == nil)

        let lake = try #require(discovery.friends.first)
        #expect(lake.isApproximate && lake.radiusM == 1000)
        #expect(lake.coordinate == GeoPoint(latitude: 43.9, longitude: 77.0))
        #expect(lake.ratingAvg == 4.5)
        #expect(lake.reports30d == 3)
        #expect(lake.lastReportAt != nil)
        #expect(lake.friends.map(\.shortName) == ["@friend_f"])
        #expect(lake.isSaved)
        #expect(lake.distanceM == nil)

        #expect(discovery.recommended.first?.title(language: "kk") == "Бұлақтар")
        #expect(discovery.items(.friends).count == 1)
    }

    @Test func cacheRoundTrip() throws {
        let discovery = try Self.decoder().decode(PlaceDiscovery.self, from: Data(Self.json.utf8))
        let cached = try JSONDecoder().decode(PlaceDiscovery.self, from: JSONEncoder().encode(discovery))
        #expect(cached == discovery)
    }

    @Test func savingUpdatesEverySection() throws {
        let id = UUID()
        let item = PlaceItem(id: id, type: .spring, name: "Родник", coordinate: GeoPoint(latitude: 43, longitude: 77))
        var discovery = PlaceDiscovery(
            nearby: [item],
            popular: [item],
            recommended: [PlaceCollection(id: UUID(), slug: "springs", title: ["ru": "Родники"], places: [item])]
        )
        discovery.setSaved(true, placeID: id)
        #expect(discovery.nearby.first?.isSaved == true)
        #expect(discovery.popular.first?.isSaved == true)
        #expect(discovery.recommended.first?.places.first?.isSaved == true)
    }

    @Test func collectionTitleFallsBackToRussian() {
        let collection = PlaceCollection(id: UUID(), slug: "x_slug", title: ["ru": "Родники"], places: [])
        #expect(collection.title(language: "en") == "Родники")
        #expect(PlaceCollection(id: UUID(), slug: "x_slug", title: [:], places: []).title(language: "en") == "x_slug")
    }

    @Test func sortOptionsDependOnQueryAndLocation() {
        #expect(!PlaceSort.options(hasQuery: false, hasLocation: false).contains(.distance))
        #expect(!PlaceSort.options(hasQuery: false, hasLocation: true).contains(.relevance))
        #expect(PlaceSort.options(hasQuery: true, hasLocation: true).first == .relevance)
        #expect(PlaceSort.defaultSort(hasQuery: false, hasLocation: true) == .distance)
        #expect(PlaceSort.defaultSort(hasQuery: false, hasLocation: false) == .name)
        #expect(PlaceSort.defaultSort(hasQuery: true, hasLocation: true) == .relevance)
        #expect(PlaceSection.friends.fullListSort == nil)
        #expect(PlaceSection.nearby.fullListSort == .distance)
    }

    @Test func queryIsActiveWithTextOrTypes() {
        #expect(!PlaceQuery(text: "   ").isActive)
        #expect(PlaceQuery(text: " озеро ").trimmedText == "озеро")
        #expect(PlaceQuery(types: [.spring]).isActive)
        #expect(PlaceQuery(text: String(repeating: "а", count: 120)).trimmedText.count == 80)
    }
}
