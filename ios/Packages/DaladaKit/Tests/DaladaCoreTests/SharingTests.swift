import Foundation
import Testing
@testable import DaladaCore

@Suite("Sharing")
struct SharingTests {
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test func decodesFriendsTripWithSegments() throws {
        let json = """
        {"id": "77777777-0000-0000-0000-000000000001", "owner_id": "11111111-1111-1111-1111-111111111111",
         "owner_username": "author", "owner_display_name": "Алия", "owner_avatar_path": null,
         "activity": "fishing", "title": "Капшагай", "note": null,
         "started_at": "2026-09-27T05:00:00Z", "ended_at": "2026-09-27T13:00:00Z",
         "moving_seconds": 18000, "distance_m": 12400, "elevation_gain_m": 85, "max_speed_mps": null,
         "visibility": "friends", "is_own": false,
         "track": {"type": "MultiLineString", "coordinates": [
           [[77.01, 43.2, 700], [77.02, 43.2, 700]],
           [[77.08, 43.2, 700], [77.09, 43.2, 700], [77.095, 43.2, 700]],
           [[77.099, 43.2, 700]]]}}
        """
        let trip = try decoder.decode(TripDetails.self, from: Data(json.utf8))
        #expect(!trip.isOwn)
        #expect(trip.owner?.username == "author")
        #expect(trip.segments.count == 2, "отрезок из одной точки не рисуется")
        #expect(trip.track.count == 5)

        let cached = try JSONDecoder().decode(TripDetails.self, from: JSONEncoder().encode(trip))
        #expect(cached == trip)
    }

    @Test func decodesOwnTripAndHiddenTrack() throws {
        let own = """
        {"id": "77777777-0000-0000-0000-000000000001", "owner_id": "11111111-1111-1111-1111-111111111111",
         "activity": "hiking", "title": "Кок-Жайляу", "started_at": "2026-09-27T05:00:00Z",
         "ended_at": "2026-09-27T09:00:00Z", "moving_seconds": 9000, "distance_m": 9000,
         "elevation_gain_m": 600, "visibility": "private", "is_own": true,
         "track": {"type": "LineString", "coordinates": [[77.0, 43.1], [77.01, 43.11]]}}
        """
        let trip = try decoder.decode(TripDetails.self, from: Data(own.utf8))
        #expect(trip.isOwn)
        #expect(trip.segments.count == 1)
        #expect(trip.with(visibility: .friends).summary.visibility == .friends)

        let hidden = own
            .replacingOccurrences(of: #""is_own": true"#, with: #""is_own": false"#)
            .replacingOccurrences(of: #"{"type": "LineString", "coordinates": [[77.0, 43.1], [77.01, 43.11]]}"#, with: "null")
        let short = try decoder.decode(TripDetails.self, from: Data(hidden.utf8))
        #expect(short.segments.isEmpty)
        #expect(!short.isOwn)
    }

    @Test func decodesTripCheckinsWithSecretPlace() throws {
        let json = """
        [{"checkin_id": "cccccccc-0000-0000-0000-000000000003", "at": "2026-09-27T05:30:00Z", "verified": false,
          "place_id": null, "place_name": null, "conditions": {}, "note": null, "catches": [], "media": []},
         {"checkin_id": "cccccccc-0000-0000-0000-000000000004", "at": "2026-09-27T05:40:00Z", "verified": true,
          "place_id": "aaaaaaaa-0000-0000-0000-000000000004", "place_name": "Для друзей",
          "conditions": {"bite": "good"}, "note": "Клюёт",
          "catches": [{"id": "dddddddd-0000-0000-0000-000000000004", "species_id": "pike", "count": 1,
                       "released": false, "weight_g": null, "length_mm": null}],
          "media": [{"id": "eeeeeeee-0000-0000-0000-000000000001", "catch_id": null,
                     "path": "u/e.jpg", "thumb_path": "u/e_thumb.jpg", "width": 1600, "height": 1200}]}]
        """
        let checkins = try decoder.decode([TripCheckin].self, from: Data(json.utf8))
        #expect(checkins[0].placeID == nil)
        #expect(checkins[0].placeName == nil)
        #expect(checkins[1].conditions.bite == .good)
        #expect(checkins[1].catches.first?.weightGrams == nil)
        #expect(checkins[1].media.count == 1)
    }

    @Test func oldTripCheckinsWithoutMediaDecode() throws {
        let json = """
        {"checkin_id": "cccccccc-0000-0000-0000-000000000001", "at": "2026-09-27T05:30:00Z", "verified": true,
         "place_id": "aaaaaaaa-0000-0000-0000-000000000001", "place_name": "Моё", "conditions": {},
         "note": null, "catches": []}
        """
        let checkin = try decoder.decode(TripCheckin.self, from: Data(json.utf8))
        #expect(checkin.media.isEmpty)
        #expect(checkin.placeName == "Моё")
    }

    @Test func decodesFeedPage() throws {
        let json = """
        [{"kind": "place", "id": "aaaaaaaa-0000-0000-0000-000000000005", "at": "2026-09-30T10:00:00Z",
          "author_id": "11111111-1111-1111-1111-111111111111", "author_username": "author",
          "author_display_name": null, "author_avatar_path": null,
          "data": {"place_type": "water_body", "name": "Приблизительное", "approximate": true}},
         {"kind": "review", "id": "bbbbbbbb-0000-0000-0000-000000000001", "at": "2026-09-29T10:00:00Z",
          "author_id": "11111111-1111-1111-1111-111111111111", "author_username": "author",
          "data": {"rating": 5}},
         {"kind": "trip", "id": "77777777-0000-0000-0000-000000000002", "at": "2026-09-28T10:00:00Z",
          "author_id": "11111111-1111-1111-1111-111111111111", "author_username": "author",
          "data": {"activity": "fishing", "title": "Публичная", "note": null,
                   "started_at": "2026-09-28T08:20:00Z", "ended_at": "2026-09-28T10:00:00Z",
                   "moving_seconds": 5400, "distance_m": 8100, "elevation_gain_m": 0}},
         {"kind": "checkin", "id": "cccccccc-0000-0000-0000-000000000004", "at": "2026-09-27T05:40:00Z",
          "author_id": "11111111-1111-1111-1111-111111111111", "author_username": "author",
          "data": {"place_id": "aaaaaaaa-0000-0000-0000-000000000004", "place_name": "Для друзей",
                   "place_type": "campsite", "verified": false, "conditions": {}, "note": null,
                   "catches": [{"id": "dddddddd-0000-0000-0000-000000000004", "species_id": "pike",
                                "count": 1, "released": false, "weight_g": null, "length_mm": null}],
                   "media": []}}]
        """
        let rows = try decoder.decode([FeedItem].self, from: Data(json.utf8))
        let page = FeedPage(rows: rows, limit: 4)
        #expect(page.items.count == 3, "отзыв из будущей версии не показываем")
        #expect(page.next == rows.last?.cursor, "курсор — по последней полученной записи")
        guard case .trip(let trip) = page.items[1].content else {
            Issue.record("ожидалась поездка")
            return
        }
        #expect(trip.distanceM == 8100)
        guard case .checkin(let checkin) = page.items[2].content else {
            Issue.record("ожидался чекин")
            return
        }
        #expect(checkin.placeType == .campsite)
        #expect(checkin.catches.count == 1)

        #expect(FeedPage(rows: rows, limit: 20).next == nil, "неполная страница — последняя")

        let cached = try JSONDecoder().decode([FeedItem].self, from: JSONEncoder().encode(page.items))
        #expect(cached == page.items)
    }

    @Test func decodesUserStats() throws {
        let json = #"[{"trips_count": 3, "distance_m": 16200, "places_count": 2, "catches_count": 1, "friends_count": 1}]"#
        let stats = try JSONDecoder().decode([UserPublicStats].self, from: Data(json.utf8))
        #expect(stats.first?.tripsCount == 3)
        #expect(stats.first?.friendsCount == 1)
    }

    @Test func privacyZoneRoundTrip() throws {
        let json = """
        {"id": "99999999-0000-0000-0000-000000000001", "name": "Дом", "radius_m": 500,
         "geom": {"type": "Point", "crs": {"type": "name", "properties": {"name": "EPSG:4326"}},
                  "coordinates": [76.9, 43.25]}}
        """
        let zone = try JSONDecoder().decode(PrivacyZone.self, from: Data(json.utf8))
        #expect(zone.center == GeoPoint(latitude: 43.25, longitude: 76.9))
        #expect(zone.radiusM == 500)
        let cached = try JSONDecoder().decode(PrivacyZone.self, from: JSONEncoder().encode(zone))
        #expect(cached == zone)
    }

    @Test func privacyZoneDraftValidation() {
        var draft = PrivacyZoneDraft(center: GeoPoint(latitude: 43.25, longitude: 76.9))
        #expect(!draft.isValid, "нужно название")
        draft.name = "  Дача  "
        #expect(draft.isValid)
        #expect(draft.trimmedName == "Дача")
        #expect(draft.ewkt == "SRID=4326;POINT(76.9 43.25)")
        draft.radiusM = 150
        #expect(!draft.isValid)
        draft.radiusM = 1000
        #expect(draft.isValid)
        draft.name = String(repeating: "д", count: 51)
        #expect(!draft.isValid)

        let zone = PrivacyZone(id: UUID(), name: "Дом", center: draft.center, radiusM: 300)
        let editing = PrivacyZoneDraft(editing: zone)
        #expect(editing.isExisting)
        #expect(editing.id == zone.id)
    }
}
