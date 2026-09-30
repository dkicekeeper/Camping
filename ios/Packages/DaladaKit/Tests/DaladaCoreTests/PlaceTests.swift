import Foundation
import Testing
@testable import DaladaCore

@Suite("Place")
struct PlaceTests {
    @Test func decodesPlacesInBoundingBoxRow() throws {
        let json = """
        [{"id": "aaaaaaaa-0000-0000-0000-000000000002", "owner_id": "11111111-1111-1111-1111-111111111111",
          "type": "fishing_spot", "name": "Залив", "lon": 77.051, "lat": 43.903, "approximate": true,
          "radius_m": 1000, "visibility": "public", "status": "published", "is_own": false}]
        """
        let places = try JSONDecoder().decode([PlaceSummary].self, from: Data(json.utf8))
        #expect(places.count == 1)
        #expect(places[0].type == .fishingSpot)
        #expect(places[0].coordinate == GeoPoint(latitude: 43.903, longitude: 77.051))
        #expect(places[0].isApproximate)
        #expect(places[0].radiusM == 1000)
        #expect(!places[0].isOwn)
    }

    @Test func decodesPlaceCardWithoutAccessPoint() throws {
        let json = """
        {"id": "aaaaaaaa-0000-0000-0000-000000000002", "owner_id": "11111111-1111-1111-1111-111111111111",
         "owner_username": "arman", "type": "campsite", "name": "Стоянка", "description": null,
         "lon": 77.2, "lat": 43.95, "approximate": true, "radius_m": 1000,
         "access_lon": null, "access_lat": null, "attributes": {}, "visibility": "friends",
         "status": "published", "is_own": false, "created_at": "2026-09-30T10:00:00+00:00"}
        """
        let place = try JSONDecoder().decode(PlaceDetails.self, from: Data(json.utf8))
        #expect(place.ownerUsername == "arman")
        #expect(place.accessPoint == nil)
        #expect(place.visibility == .friends)
        #expect(!place.isEditorial)
        #expect(place.source == nil)
    }

    @Test func editorialPlaceKeepsItsSourceInCache() throws {
        let json = """
        {"id": "aaaaaaaa-0000-0000-0000-000000000003", "owner_id": "da1ada00-0000-4000-8000-000000000001",
         "owner_username": "dalada", "type": "water_body", "name": "Бартогайское водохранилище",
         "description": null, "lon": 78.5055, "lat": 43.3537, "approximate": false, "radius_m": 0,
         "access_lon": null, "access_lat": null, "attributes": {"source": "osm", "osm": "r19802418"},
         "visibility": "public", "status": "published", "is_own": false}
        """
        let place = try JSONDecoder().decode(PlaceDetails.self, from: Data(json.utf8))
        #expect(place.isEditorial)
        #expect(place.source == .osm)

        let cached = try JSONDecoder().decode(PlaceDetails.self, from: JSONEncoder().encode(place))
        #expect(cached == place)
    }

    @Test func draftValidation() {
        var draft = PlaceDraft(coordinate: .almaty)
        #expect(!draft.isValid)
        draft.name = "   "
        #expect(!draft.isValid)
        draft.name = " Капшагай, северный берег "
        #expect(draft.isValid)
        #expect(draft.trimmedName == "Капшагай, северный берег")
        draft.name = String(repeating: "а", count: 81)
        #expect(!draft.isValid)
    }

    @Test func privatePlacesAreNeverApproximate() {
        var draft = PlaceDraft(coordinate: .almaty, visibility: .private, isApproximate: true)
        #expect(!draft.effectiveApproximate)
        draft.visibility = .friends
        #expect(draft.effectiveApproximate)
    }
}

@Suite("Geo")
struct GeoTests {
    @Test func circleIsClosedAndHasRequestedRadius() {
        let center = GeoPoint(latitude: 43.9, longitude: 77.05)
        let ring = center.circle(radiusM: 1000, segments: 64)
        #expect(ring.count == 65)
        #expect(ring.first == ring.last)
        for point in ring {
            #expect(abs(center.distance(to: point) - 1000) < 1)
        }
    }

    @Test func clampedBoxKeepsCenterAndLimitsSpan() {
        let box = GeoBoundingBox(minLongitude: 60, minLatitude: 35, maxLongitude: 90, maxLatitude: 55)
        let clamped = box.clamped(maxSpanDegrees: 9.5)
        #expect(abs((clamped.maxLongitude - clamped.minLongitude) - 9.5) < 1e-9)
        #expect(abs((clamped.maxLatitude - clamped.minLatitude) - 9.5) < 1e-9)
        #expect(clamped.center == box.center)
    }

    @Test func smallBoxIsUnchanged() {
        let box = GeoBoundingBox(minLongitude: 76.5, minLatitude: 43.5, maxLongitude: 77.5, maxLatitude: 44.3)
        let clamped = box.clamped()
        #expect(abs(clamped.minLongitude - box.minLongitude) < 1e-9)
        #expect(abs(clamped.maxLatitude - box.maxLatitude) < 1e-9)
    }
}
