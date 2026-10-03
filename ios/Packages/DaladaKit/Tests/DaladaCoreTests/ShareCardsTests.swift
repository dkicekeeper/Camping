import Foundation
import Testing
@testable import DaladaCore

@Suite("ShareCards")
struct ShareCardsTests {
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test func decodesTripCardWithTrack() throws {
        let cards = try decoder.decode([TripShareCard].self, from: Data("""
        [{"activity": "fishing", "title": "Утро на косе", "started_at": "2026-10-02T05:00:00Z",
          "ended_at": "2026-10-02T08:00:00Z", "moving_seconds": 5400, "distance_m": 8100, "elevation_gain_m": 0,
          "track": {"type": "LineString", "coordinates": [[77.002, 43.3], [77.05, 43.3], [77.09, 43.31]]}}]
        """.utf8))
        #expect(cards[0].title == "Утро на косе")
        #expect(cards[0].segments.count == 1)
        #expect(cards[0].segments[0].count == 3)
    }

    @Test func tripCardWithoutTrackHasNoSegments() throws {
        let card = try decoder.decode(TripShareCard.self, from: Data("""
        {"activity": "hiking", "title": "Дом", "started_at": "2026-10-02T05:00:00Z",
         "ended_at": "2026-10-02T06:00:00Z", "moving_seconds": 600, "distance_m": 300, "elevation_gain_m": 0,
         "track": null}
        """.utf8))
        #expect(card.segments.isEmpty)
    }

    @Test func decodesCatchCard() throws {
        let card = try decoder.decode(CatchShareCard.self, from: Data("""
        {"species_id": "pike", "weight_g": 2400, "length_mm": null, "count": 1, "released": true,
         "at": "2026-10-02T06:00:00Z", "photo_path": null, "place_name": "Капшагай"}
        """.utf8))
        #expect(card.speciesID == "pike")
        #expect(card.weightGrams == 2400)
        #expect(card.lengthMillimeters == nil)
        #expect(card.released)
        #expect(card.placeName == "Капшагай")
    }

    @Test func formatsAndSiteLabel() {
        #expect(ShareCardFormat.story.width * ShareCardFormat.scale == 1080)
        #expect(ShareCardFormat.story.height * ShareCardFormat.scale == 1920)
        #expect(ShareCardFormat.post.height * ShareCardFormat.scale == 1350)
        #expect(ShareCardLink.siteLabel == "dkicekeeper.github.io/Dalada")
    }
}
