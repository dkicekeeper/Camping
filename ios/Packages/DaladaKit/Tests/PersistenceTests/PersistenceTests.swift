import DaladaCore
import Foundation
import GRDB
@testable import Persistence
import Testing

@Suite("Outbox")
struct OutboxTests {
    let owner = UUID()
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func photo(_ byte: UInt8) -> PhotoDraft {
        PhotoDraft(full: Data([byte, 1]), thumbnail: Data([byte, 2]), width: 1600, height: 1200)
    }

    private func draft(at: Date? = nil) -> CheckinDraft {
        CheckinDraft(
            placeID: UUID(),
            at: at ?? start,
            conditions: CheckinConditions(bite: .good, water: .muddy),
            note: "Клюёт у камыша",
            visibility: .public,
            catches: [
                CatchDraft(speciesID: "pike", weightKg: 2.5, lengthCm: 65, method: .spinning, photo: photo(9)),
                CatchDraft(speciesID: "perch", count: 5),
            ],
            photos: [photo(1), photo(2)],
            deviceLocation: GeoPoint(latitude: 43.9, longitude: 77.05)
        )
    }

    @Test func storesWholeCheckinAndRestoresIt() async throws {
        let outbox = try LocalDatabase.inMemory().outbox
        let original = draft()
        try await outbox.enqueue(original, owner: owner, placeName: "Капшагай", now: start)

        let due = try await outbox.due(owner: owner, now: start)
        let restored = try #require(due.first)
        #expect(restored == original)
        #expect(restored.catches[0].photo == original.catches[0].photo)
        #expect(restored.photos.map(\.full) == [Data([1, 1]), Data([2, 1])])
        #expect(restored.photoUploads.count == 3)
    }

    @Test func dueRespectsOwnerAndRetryPause() async throws {
        let outbox = try LocalDatabase.inMemory().outbox
        let item = draft()
        try await outbox.enqueue(item, owner: owner, placeName: "Место", now: start)
        #expect(try await outbox.due(owner: UUID(), now: start).isEmpty)

        let attempts = try await outbox.recordFailedAttempt(item.id, error: nil, now: start)
        #expect(attempts == 1)
        #expect(try await outbox.due(owner: owner, now: start.addingTimeInterval(10)).isEmpty)
        #expect(try await outbox.due(owner: owner, now: start.addingTimeInterval(15)).count == 1)
        #expect(try await outbox.nextAttemptDate(owner: owner) == start.addingTimeInterval(15))

        try await outbox.makeDue(owner: owner, now: start.addingTimeInterval(1))
        #expect(try await outbox.due(owner: owner, now: start.addingTimeInterval(1)).count == 1)
    }

    @Test func failedItemsWaitForUser() async throws {
        let outbox = try LocalDatabase.inMemory().outbox
        let item = draft()
        try await outbox.enqueue(item, owner: owner, placeName: "Место", now: start)
        try await outbox.markFailed(item.id, error: "place not found")

        #expect(try await outbox.due(owner: owner, now: start.addingTimeInterval(3600)).isEmpty)
        #expect(try await outbox.nextAttemptDate(owner: owner) == nil)
        let pending = try await outbox.pending(owner: owner)
        #expect(pending.first?.state == .failed("place not found"))
        #expect(pending.first?.photoCount == 3)
        #expect(pending.first?.catches.map(\.speciesID) == ["pike", "perch"])

        try await outbox.requeue(item.id, now: start)
        #expect(try await outbox.due(owner: owner, now: start).count == 1)
        #expect(try await outbox.pending(owner: owner).first?.state == .waiting)
    }

    @Test func removingCheckinRemovesPhotos() async throws {
        let database = try LocalDatabase.inMemory()
        let item = draft()
        try await database.outbox.enqueue(item, owner: owner, placeName: "Место", now: start)
        try await database.outbox.remove(item.id)
        let photos = try await database.writer.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM outbox_photo") }
        #expect(photos == 0)
        #expect(try await database.outbox.pending(owner: owner).isEmpty)
    }

    @Test func oldestCheckinGoesFirst() async throws {
        let outbox = try LocalDatabase.inMemory().outbox
        let later = draft(at: start.addingTimeInterval(600))
        let earlier = draft(at: start)
        try await outbox.enqueue(later, owner: owner, placeName: "Место", now: start)
        try await outbox.enqueue(earlier, owner: owner, placeName: "Место", now: start)
        #expect(try await outbox.due(owner: owner, now: start).first?.id == earlier.id)
    }

    @Test func fileDatabaseSurvivesReopening() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dalada-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let item = draft()
        try await LocalDatabase.open(at: url).outbox.enqueue(item, owner: owner, placeName: "Место", now: start)
        let reopened = try LocalDatabase.open(at: url)
        #expect(try await reopened.outbox.due(owner: owner, now: start).first?.id == item.id)
    }
}

@Suite("Cache")
struct CacheTests {
    @Test func roundTripsServerModels() async throws {
        let cache = try LocalDatabase.inMemory().cache
        let json = """
        {"id": "aaaaaaaa-0000-0000-0000-000000000002", "owner_id": "11111111-1111-1111-1111-111111111111",
         "owner_username": "arman", "type": "campsite", "name": "Стоянка", "description": "У реки",
         "lon": 77.2, "lat": 43.95, "approximate": false, "radius_m": 1000,
         "access_lon": 77.21, "access_lat": 43.96, "visibility": "friends", "status": "published", "is_own": false}
        """
        let place = try JSONDecoder().decode(PlaceDetails.self, from: Data(json.utf8))
        let viewer = UUID()
        try await cache.save(place, for: .place(place.id, viewer: viewer))
        let cached = try await cache.load(PlaceDetails.self, for: .place(place.id, viewer: viewer))
        #expect(cached == place)
        #expect(cached?.accessPoint == GeoPoint(latitude: 43.96, longitude: 77.21))
        #expect(try await cache.load(PlaceDetails.self, for: .place(place.id, viewer: nil)) == nil)
    }

    @Test func roundTripsReportsWithDates() async throws {
        let cache = try LocalDatabase.inMemory().cache
        let json = """
        [{"checkin_id": "cccccccc-0000-0000-0000-000000000001", "author_id": "11111111-1111-1111-1111-111111111111",
          "author_username": "arman", "author_display_name": null, "at": "2026-09-30T10:00:00Z",
          "verified": true, "conditions": {"bite": "good"}, "note": null, "is_own": false,
          "catches": [{"id": "dddddddd-0000-0000-0000-000000000001", "species_id": "pike", "count": 1,
                       "released": false, "weight_g": null, "length_mm": 650}],
          "media": [{"id": "eeeeeeee-0000-0000-0000-000000000001", "catch_id": null, "path": "a/e.jpg",
                     "thumb_path": "a/e_thumb.jpg", "width": 1600, "height": 1200}]}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reports = try decoder.decode([PlaceReport].self, from: Data(json.utf8))
        let key = CacheKey.reports(UUID(), viewer: nil)
        try await cache.save(reports, for: key)
        #expect(try await cache.load([PlaceReport].self, for: key) == reports)
    }

    @Test func signOutRemovesOnlyThatUsersData() async throws {
        let database = try LocalDatabase.inMemory()
        let cache = database.cache
        let alice = UUID()
        let bob = UUID()
        try await cache.save(["a"], for: .myCatches(alice))
        try await cache.save(["b"], for: .myCatches(bob))
        try await cache.save(["species"], for: .species)
        try await cache.save(["guest"], for: .mapPlaces(viewer: nil))

        try await cache.removeUserData(alice)
        #expect(try await cache.load([String].self, for: .myCatches(alice)) == nil)
        #expect(try await cache.load([String].self, for: .myCatches(bob)) == ["b"])
        #expect(try await cache.load([String].self, for: .species) == ["species"])
        #expect(try await cache.load([String].self, for: .mapPlaces(viewer: nil)) == ["guest"])
    }

    @Test func incompatibleCacheIsIgnored() async throws {
        let cache = try LocalDatabase.inMemory().cache
        try await cache.save(["не профиль"], for: .profile(UUID()))
        #expect(try await cache.load(UserProfile.self, for: .species) == nil)
        try await cache.save(["x"], for: .species)
        #expect(try await cache.load([FishSpecies].self, for: .species) == nil)
    }
}

@Suite("Trips")
struct TripStoreTests {
    let owner = UUID()
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func point(_ seconds: Double, altitude: Double? = 480, startsSegment: Bool = false) -> TrackPoint {
        TrackPoint(latitude: 43.9 + seconds / 100_000, longitude: 77.0, altitude: altitude,
                   horizontalAccuracy: 5, speed: 1.2, timestamp: start.addingTimeInterval(seconds),
                   startsSegment: startsSegment)
    }

    @Test func activeTripSurvivesReopening() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dalada-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID()
        do {
            let trips = try LocalDatabase.open(at: url).trips
            try await trips.start(id: id, activity: .hiking, at: start)
            try await trips.append(point(0), to: id)
            try await trips.append(point(30, altitude: nil), to: id)
            try await trips.setState(.paused)
            try await trips.append(point(90, startsSegment: true), to: id)
        }
        let active = try #require(try await LocalDatabase.open(at: url).trips.active())
        #expect(active.id == id)
        #expect(active.activity == .hiking)
        #expect(active.state == .paused)
        #expect(active.points == [point(0), point(30, altitude: nil), point(90, startsSegment: true)])
    }

    @Test func finishMovesTripToOutboxWithPoints() async throws {
        let database = try LocalDatabase.inMemory()
        let id = UUID()
        try await database.trips.start(id: id, activity: .fishing, at: start)
        for seconds in [0.0, 30, 60] { try await database.trips.append(point(seconds), to: id) }
        try await database.trips.finishActive(owner: owner, title: "Капшагай", note: "Судак", visibility: .friends,
                                              activity: .fishing, endedAt: start.addingTimeInterval(3600), now: start)

        #expect(try await database.trips.active() == nil)
        let due = try #require(try await database.outbox.dueTrips(owner: owner, now: start).first)
        #expect(due.id == id)
        #expect(due.title == "Капшагай")
        #expect(due.visibility == .friends)
        #expect(due.points.count == 3)
        #expect(due.endedAt == start.addingTimeInterval(3600))
        #expect(try await database.outbox.pendingTrips(owner: owner).first?.state == .waiting)

        try await database.outbox.recordFailedAttempt(id, error: "503", now: start)
        #expect(try await database.outbox.dueTrips(owner: owner, now: start).isEmpty)
        #expect(try await database.outbox.nextAttemptDate(owner: owner) == start.addingTimeInterval(15))

        try await database.outbox.remove(id)
        let points = try await database.writer.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM track_point") }
        #expect(points == 0)
        #expect(try await database.outbox.pendingTrips(owner: owner).isEmpty)
    }

    @Test func discardingActiveTripRemovesPoints() async throws {
        let database = try LocalDatabase.inMemory()
        let id = UUID()
        try await database.trips.start(id: id, activity: .fishing, at: start)
        try await database.trips.append(point(0), to: id)
        try await database.trips.discardActive()
        #expect(try await database.trips.active() == nil)
        let points = try await database.writer.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM track_point") }
        #expect(points == 0)
    }
}
