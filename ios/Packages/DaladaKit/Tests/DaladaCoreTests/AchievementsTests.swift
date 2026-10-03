import Foundation
import Testing
@testable import DaladaCore

@Suite("Достижения")
struct AchievementsTests {
    @Test func decodesRPCRows() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([Achievement].self, from: Data("""
        [{"achievement": "first_trip", "progress": 2, "target": 1, "earned_at": "2026-10-03T10:00:00Z", "is_new": true},
         {"achievement": "distance_100", "progress": 86, "target": 100, "earned_at": null, "is_new": false}]
        """.utf8))
        #expect(rows.count == 2)
        #expect(rows[0].kind == .firstTrip)
        #expect(rows[0].isEarned && rows[0].isNew)
        #expect(rows[0].fraction == 1)
        #expect(rows[1].kind == .distance100)
        #expect(!rows[1].isEarned)
        #expect(abs(rows[1].fraction - 0.86) < 0.0001)
    }

    @Test func catalogMatchesServerCodes() {
        #expect(AchievementKind.allCases.map(\.rawValue) == [
            "first_trip", "distance_100", "nights_5", "first_catch", "species_5",
            "trophy_3kg", "places_5", "first_public_place", "reviews_5", "accepted_edit",
        ])
        #expect(AchievementKind.distance100.unit == .kilometers)
        #expect(AchievementKind.trophy3kg.unit == .grams)
        #expect(AchievementKind.reviews5.unit == .count)
    }

    @Test func fractionIsClamped() {
        #expect(Achievement(id: "species_5", progress: 9, target: 5).fraction == 1)
        #expect(Achievement(id: "species_5", progress: -1, target: 5).fraction == 0)
        #expect(Achievement(id: "species_5", progress: 3, target: 0).fraction == 0)
    }

    @Test func listHelpers() {
        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 2_000)
        let list = [
            Achievement(id: "first_trip", progress: 1, target: 1, earnedAt: old),
            Achievement(id: "distance_100", progress: 40, target: 100),
            Achievement(id: "species_5", progress: 4, target: 5),
            Achievement(id: "first_catch", progress: 1, target: 1, earnedAt: recent, isNew: true),
            Achievement(id: "future_badge", progress: 0, target: 1, earnedAt: recent, isNew: true),
        ]
        #expect(list.known.count == 4)
        #expect(list.earnedRecentFirst.map(\.id) == ["first_catch", "first_trip"])
        #expect(list.fresh.map(\.id) == ["first_catch"])
        #expect(list.nextUp?.id == "species_5")
    }
}
