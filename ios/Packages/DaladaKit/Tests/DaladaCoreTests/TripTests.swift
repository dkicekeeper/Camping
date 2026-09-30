import Foundation
import Testing
@testable import DaladaCore

@Suite("Trip")
struct TripTests {
    let start = Date(timeIntervalSince1970: 1_790_485_200)

    /// Точка на `metersNorth` к северу от старта через `seconds` секунд.
    private func point(
        _ seconds: Double,
        metersNorth: Double,
        altitude: Double? = nil,
        accuracy: Double = 5,
        speed: Double? = nil,
        startsSegment: Bool = false
    ) -> TrackPoint {
        let coordinate = GeoPoint(latitude: 43.9, longitude: 77.0).destination(distanceM: metersNorth, bearingDegrees: 0)
        return TrackPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: altitude,
                          horizontalAccuracy: accuracy, speed: speed,
                          timestamp: start.addingTimeInterval(seconds), startsSegment: startsSegment)
    }

    @Test func filterDropsNoiseAndJumps() {
        let filter = TrackFilter()
        let first = point(0, metersNorth: 0)
        #expect(filter.accepts(first, after: nil))
        #expect(!filter.accepts(point(0, metersNorth: 0, accuracy: 80), after: nil), "грубая точка")
        #expect(!filter.accepts(point(5, metersNorth: 2), after: first), "дрожание на месте")
        #expect(filter.accepts(point(61, metersNorth: 2), after: first), "стоим, но раз в минуту пишем")
        #expect(filter.accepts(point(5, metersNorth: 20), after: first), "идём")
        #expect(!filter.accepts(point(5, metersNorth: 2000), after: first), "прыжок 400 м/с")
        #expect(!filter.accepts(point(0, metersNorth: 20), after: first), "то же время")
        #expect(filter.accepts(point(600, metersNorth: 5000, startsSegment: true), after: first), "после паузы")
    }

    @Test func statsCountMovingTimeAndSkipStanding() {
        let points = [
            point(0, metersNorth: 0),
            point(60, metersNorth: 100),      // шли минуту
            point(120, metersNorth: 105),     // стоим (5 м за минуту)
            point(1800, metersNorth: 110),    // долго стоим
            point(1860, metersNorth: 210),    // снова минуту шли
        ]
        let stats = TrackStats(points: points)
        #expect(abs(stats.distanceM - 210) < 1)
        #expect(stats.movingSeconds == 120)
        #expect(stats.pointCount == 5)
    }

    @Test func pauseDoesNotCountTheGap() {
        let points = [
            point(0, metersNorth: 0),
            point(60, metersNorth: 100),
            point(3600, metersNorth: 20_000, startsSegment: true), // ехали на машине на паузе
            point(3660, metersNorth: 20_100),
        ]
        let stats = TrackStats(points: points)
        #expect(abs(stats.distanceM - 200) < 1)
        #expect(stats.movingSeconds == 120)
    }

    @Test func elevationGainIgnoresNoise() {
        let altitudes: [Double] = [500, 502, 499, 501, 506, 510, 508, 515, 503, 509]
        let points = altitudes.enumerated().map { index, altitude in
            point(Double(index) * 30, metersNorth: Double(index) * 50, altitude: altitude)
        }
        // Подъёмы ≥ 4 м от последней опорной точки: 500→506 (+6), 506→510 (+4), 510→515 (+5),
        // спуск до 503 переносит опору, 503→509 (+6).
        #expect(TrackStats(points: points).elevationGainM == 21)
    }

    @Test func maxSpeedOnlyFromAccuratePoints() {
        let points = [
            point(0, metersNorth: 0, speed: 3),
            point(10, metersNorth: 30, accuracy: 40, speed: 30),
            point(20, metersNorth: 60, speed: 4.5),
        ]
        #expect(TrackStats(points: points).maxSpeedMps == 4.5)
    }

    @Test func encodesTrackAsEWKT() {
        let points = [
            TrackPoint(latitude: 43.9000014, longitude: 77.0000016, altitude: 480.54, horizontalAccuracy: 5, timestamp: start),
            TrackPoint(latitude: 43.905, longitude: 77.01, horizontalAccuracy: 5, timestamp: start.addingTimeInterval(60.4)),
        ]
        #expect(TrackEncoding.ewkt(points)
            == "SRID=4326;LINESTRING ZM (77.000002 43.900001 480.5 1790485200, 77.010000 43.905000 0.0 1790485260)")
        #expect(TrackEncoding.ewkt(Array(points.prefix(1))) == nil)
    }

    @Test func draftValidation() {
        var draft = TripDraft(title: "  ", startedAt: start, endedAt: start.addingTimeInterval(60))
        #expect(!draft.isValid)
        draft.title = "Капшагай"
        #expect(draft.isValid)
        draft.endedAt = start.addingTimeInterval(-1)
        #expect(!draft.isValid)
    }

    @Test func decodesTripWithTrackAndCachesIt() throws {
        let json = """
        {"id": "77777777-0000-0000-0000-000000000001", "activity": "fishing", "title": "Капшагай",
         "note": null, "started_at": "2026-09-27T05:00:00Z", "ended_at": "2026-09-27T13:00:00Z",
         "moving_seconds": 18000, "distance_m": 12400, "elevation_gain_m": 85, "max_speed_mps": 16.5,
         "visibility": "private",
         "track": {"type": "LineString", "coordinates": [[77.000001, 43.900001, 480.5], [77.01, 43.905, 482]]}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let trip = try decoder.decode(TripDetails.self, from: Data(json.utf8))
        #expect(trip.summary.activity == .fishing)
        #expect(trip.summary.duration == 8 * 3600)
        #expect(trip.track == [GeoPoint(latitude: 43.900001, longitude: 77.000001), GeoPoint(latitude: 43.905, longitude: 77.01)])

        let cached = try JSONDecoder().decode(TripDetails.self, from: JSONEncoder().encode(trip))
        #expect(cached == trip)
    }

    @Test func decodesStats() throws {
        let json = """
        [{"trips_count": 2, "distance_m": 42500, "moving_seconds": 36000, "days_outdoors": 5,
          "checkins_count": 2, "catches_count": 11, "species_count": 2, "places_count": 2}]
        """
        let stats = try JSONDecoder().decode([UserStats].self, from: Data(json.utf8))
        #expect(stats.first?.daysOutdoors == 5)
        #expect(stats.first?.catchesCount == 11)
    }

    @Test func decodesTripWithoutTrack() throws {
        let json = """
        {"id": "77777777-0000-0000-0000-000000000002", "activity": "camping", "title": "Ночёвка",
         "note": "У реки", "started_at": 1790485200, "ended_at": 1790485260,
         "moving_seconds": 0, "distance_m": 0, "elevation_gain_m": 0, "max_speed_mps": null,
         "visibility": "friends", "track": null}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let trip = try decoder.decode(TripDetails.self, from: Data(json.utf8))
        #expect(trip.track.isEmpty)
        #expect(trip.summary.note == "У реки")
    }
}
