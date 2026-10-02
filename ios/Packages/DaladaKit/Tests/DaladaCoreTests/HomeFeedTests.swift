import Foundation
import Testing
@testable import DaladaCore

@Suite("HomeFeed")
struct HomeFeedTests {
    private func decode(_ json: String) throws -> [FeedItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([FeedItem].self, from: Data(json.utf8))
    }

    @Test func decodesThreadAndTripWithTrack() throws {
        let items = try decode("""
        [{"kind": "thread", "id": "dddddddd-0000-0000-0000-000000000041", "at": "2026-10-01T10:00:00Z",
          "author_id": "33333333-3333-3333-3333-333333333333", "author_username": "stranger",
          "author_display_name": null, "author_avatar_path": null,
          "data": {"place_id": "aaaaaaaa-0000-0000-0000-000000000001", "place_name": "Озеро",
                   "place_type": "water_body", "title": "Как проехать?", "body": "Дорога раскисла?",
                   "posts_count": 3, "last_activity_at": "2026-10-01T12:00:00Z"}},
         {"kind": "trip", "id": "77777777-0000-0000-0000-000000000011", "at": "2026-09-30T10:00:00Z",
          "author_id": "11111111-1111-1111-1111-111111111111", "author_username": "me",
          "author_display_name": "Я", "author_avatar_path": null,
          "data": {"activity": "fishing", "title": "Утро", "note": null,
                   "started_at": "2026-09-30T08:00:00Z", "ended_at": "2026-09-30T10:00:00Z",
                   "moving_seconds": 3600, "distance_m": 2400, "elevation_gain_m": 12,
                   "track": {"type": "MultiLineString", "coordinates": [[[77.0, 43.2], [77.01, 43.2]], [[77.02, 43.2]]]}}}]
        """)
        guard case .thread(let thread) = items[0].content else {
            Issue.record("ожидалось обсуждение")
            return
        }
        #expect(thread.title == "Как проехать?")
        #expect(thread.postsCount == 3)
        #expect(items[0].reactionKey == nil)
        guard case .trip(let trip) = items[1].content else {
            Issue.record("ожидалась поездка")
            return
        }
        #expect(trip.segments.count == 1)
        #expect(trip.segments[0].count == 2)
        #expect(items[1].reactionKey == ReactionKey(.trip, items[1].id))
    }

    @Test func tripWithoutTrackAndCacheRoundTrip() throws {
        let items = try decode("""
        [{"kind": "trip", "id": "77777777-0000-0000-0000-000000000012", "at": "2026-09-30T10:00:00Z",
          "author_id": "22222222-2222-2222-2222-222222222222", "author_username": "friend",
          "author_display_name": null, "author_avatar_path": null,
          "data": {"activity": "hiking", "title": "Перевал", "note": "Ветер",
                   "started_at": "2026-09-30T08:00:00Z", "ended_at": "2026-09-30T10:00:00Z",
                   "moving_seconds": 3600, "distance_m": 5000, "elevation_gain_m": 300, "track": null}},
         {"kind": "thread", "id": "dddddddd-0000-0000-0000-000000000042", "at": "2026-10-01T10:00:00Z",
          "author_id": "33333333-3333-3333-3333-333333333333", "author_username": null,
          "author_display_name": null, "author_avatar_path": null,
          "data": {"place_id": "aaaaaaaa-0000-0000-0000-000000000001", "place_name": "Озеро",
                   "place_type": "water_body", "title": "Лёд", "body": "Держит?", "posts_count": 0,
                   "last_activity_at": null}}]
        """)
        guard case .trip(let trip) = items[0].content else {
            Issue.record("ожидалась поездка")
            return
        }
        #expect(trip.segments.isEmpty)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cached = try decoder.decode([FeedItem].self, from: encoder.encode(items))
        #expect(cached == items)
    }

    @Test func trackPreviewKeepsProportionsAndNorthUp() {
        // На восток 0.02° и на север 0.01° на широте 60°: по местности ширина ≈ высоте.
        let preview = TrackPreview.normalized([[
            GeoPoint(latitude: 60.0, longitude: 30.0),
            GeoPoint(latitude: 60.0, longitude: 30.02),
            GeoPoint(latitude: 60.01, longitude: 30.02),
        ]])
        #expect(preview.count == 1)
        let points = preview[0]
        #expect(abs(points[0].x - 0) < 0.01)
        #expect(abs(points[1].x - 1) < 0.01)
        // Север сверху: последняя точка выше (меньше y).
        #expect(points[2].y < points[1].y)
        #expect(abs(points[2].y - 0) < 0.02)
        #expect(abs(points[1].y - 1) < 0.02)
    }

    @Test func trackPreviewCentersNarrowTrack() {
        let preview = TrackPreview.normalized([[
            GeoPoint(latitude: 43.0, longitude: 77.0),
            GeoPoint(latitude: 43.01, longitude: 77.0),
        ]])
        #expect(preview[0][0].x == 0.5)
        #expect(preview[0][1].x == 0.5)
        #expect(TrackPreview.normalized([[GeoPoint(latitude: 43, longitude: 77)]]).isEmpty)
        #expect(TrackPreview.normalized([]).isEmpty)
    }
}
