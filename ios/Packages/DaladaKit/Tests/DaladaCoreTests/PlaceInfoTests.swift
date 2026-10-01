import Foundation
import Testing
@testable import DaladaCore

@Suite("PlaceInfo")
struct PlaceInfoTests {
    private func card(attributes: String, isOwn: Bool = false, approximate: Bool = false,
                      visibility: String = "public") throws -> PlaceDetails {
        let json = """
        {"id": "aaaaaaaa-0000-0000-0000-000000000001", "owner_id": "11111111-1111-1111-1111-111111111111",
         "owner_username": "arman", "type": "water_body", "name": "Озеро", "description": null,
         "lon": 77.05, "lat": 43.9, "approximate": \(approximate), "radius_m": 0,
         "access_lon": null, "access_lat": null, "attributes": \(attributes), "visibility": "\(visibility)",
         "status": "published", "is_own": \(isOwn)}
        """
        return try JSONDecoder().decode(PlaceDetails.self, from: Data(json.utf8))
    }

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    @Test func decodesInfoFromPlaceCard() throws {
        let place = try card(attributes: """
        {"source": "osm", "osm": "n1", "species": ["pike", "perch", "pike"], "access": ["dirt", "teleport"],
         "fee": "paid", "price_kzt": 3000, "price_unit": "day", "methods": ["shore", "spinning"],
         "amenities": ["toilet", "boat_rental"], "signal": "weak", "months": [5, 6, 13],
         "features": "Коряги у берега", "legacy": 1}
        """)
        #expect(place.source == .osm)
        #expect(place.info.species == ["pike", "perch"])
        #expect(place.info.access == [.dirt])
        #expect(place.info.fee == .paid)
        #expect(place.info.priceKZT == 3000)
        #expect(place.info.priceUnit == .day)
        #expect(place.info.methods == [.shore, .spinning])
        #expect(place.info.amenities == [.toilet, .boatRental])
        #expect(place.info.signal == .weak)
        #expect(place.info.months == [5, 6])
        #expect(place.info.features == "Коряги у берега")
    }

    @Test func badValuesDoNotBreakTheCard() throws {
        let place = try card(attributes: #"{"species": "pike", "fee": 1, "months": "may", "price_kzt": 10.5}"#)
        #expect(place.info.isEmpty)
    }

    @Test func cacheKeepsSourceAndInfo() throws {
        let place = try card(attributes: #"{"source": "editorial", "fee": "free", "months": [12, 1]}"#)
        let cached = try JSONDecoder().decode(PlaceDetails.self, from: JSONEncoder().encode(place))
        #expect(cached == place)
        #expect(cached.source == .editorial)
        #expect(cached.info.fee == .free)
    }

    @Test func encodesOnlyFilledFieldsInStableOrder() throws {
        let attributes = PlaceAttributes(
            species: ["pike", "pike", "carp"],
            access: [.boat, .asphalt],
            fee: .paid,
            priceKZT: 2000,
            priceUnit: .kg,
            contact: "  ",
            methods: [.ice, .shore],
            amenities: [],
            months: [9, 5],
            features: "  Глубина 3 м  "
        )
        let object = try json(attributes)
        #expect(Set(object.keys) == ["species", "access", "fee", "price_kzt", "price_unit", "methods", "months", "features"])
        #expect(object["species"] as? [String] == ["pike", "carp"])
        #expect(object["access"] as? [String] == ["asphalt", "boat"])
        #expect(object["methods"] as? [String] == ["shore", "ice"])
        #expect(object["months"] as? [Int] == [5, 9])
        #expect(object["features"] as? String == "Глубина 3 м")
    }

    @Test func priceOnlyForPaidPlaces() throws {
        var attributes = PlaceAttributes(fee: .free, priceKZT: 1000, priceUnit: .entry)
        #expect(try json(attributes).keys.sorted() == ["fee"])
        attributes.fee = .paid
        attributes.priceKZT = nil
        #expect(try json(attributes).keys.sorted() == ["fee"])
        #expect(PlaceAttributes(contact: " ").isEmpty)
    }

    @Test func validation() {
        #expect(PlaceAttributes().isValid)
        #expect(!PlaceAttributes(fee: .paid, priceKZT: -1).isValid)
        #expect(!PlaceAttributes(contact: String(repeating: "1", count: 101)).isValid)
        #expect(!PlaceAttributes(features: String(repeating: "я", count: 1001)).isValid)
        #expect(PlaceAttributes(features: String(repeating: "я", count: 1000)).isValid)
    }

    @Test func monthSpans() {
        typealias Span = PlaceAttributes.MonthSpan
        #expect(PlaceAttributes.monthSpans([]) == [])
        #expect(PlaceAttributes.monthSpans([5, 6, 7, 9]) == [Span(from: 5, to: 7), Span(from: 9, to: 9)])
        #expect(PlaceAttributes.monthSpans([11, 12, 1, 2]) == [Span(from: 11, to: 2)])
        #expect(PlaceAttributes.monthSpans([1, 6, 12]) == [Span(from: 6, to: 6), Span(from: 12, to: 1)])
        #expect(PlaceAttributes.monthSpans(Set(1...12)) == [Span(from: 1, to: 12)])
    }

    @Test func summaryOfLastWeek() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 24 * 60 * 60
        let entries: [(at: Date, bite: CheckinConditions.Bite?)] = [
            (now - 1 * day, .good),
            (now - 2 * day, .weak),
            (now - 3 * day, .good),
            (now - 4 * day, nil),
            (now - 9 * day, .excellent),
        ]
        let summary = PlaceReportsSummary.make(entries: entries, limit: 50, now: now)
        #expect(summary == PlaceReportsSummary(count: 4, isLowerBound: false, bite: .good))
    }

    @Test func summaryTieGoesToTheLatest() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let hour: TimeInterval = 60 * 60
        let summary = PlaceReportsSummary.make(
            entries: [(now - 3 * hour, .good), (now - 1 * hour, .weak)],
            limit: 50,
            now: now
        )
        #expect(summary?.bite == .weak)
        #expect(PlaceReportsSummary.make(entries: [(now - 1 * hour, nil)], limit: 50, now: now)?.bite == nil)
    }

    @Test func summaryWithoutRecentReports() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(PlaceReportsSummary.make(entries: [], limit: 50, now: now) == nil)
        #expect(PlaceReportsSummary.make(entries: [(now - 8 * 24 * 60 * 60, .good)], limit: 50, now: now) == nil)
    }

    @Test func summaryIsLowerBoundWhenEverythingLoadedIsRecent() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = (0..<3).map { (at: now - Double($0) * 60, bite: CheckinConditions.Bite?.none) }
        #expect(PlaceReportsSummary.make(entries: entries, limit: 3, now: now)?.isLowerBound == true)
        #expect(PlaceReportsSummary.make(entries: entries, limit: 4, now: now)?.isLowerBound == false)
    }

    @Test func placeLink() {
        let id = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
        let url = PlaceLink.url(placeID: id)
        #expect(url.absoluteString == "dalada://place/aaaaaaaa-0000-0000-0000-000000000001")
        #expect(PlaceLink.placeID(from: url) == id)
        #expect(PlaceLink.placeID(from: URL(string: "dalada://thread/aaaaaaaa-0000-0000-0000-000000000001")!) == nil)
        #expect(PlaceLink.placeID(from: URL(string: "dalada://place/nope")!) == nil)
        #expect(ThreadLink.threadID(from: url) == nil)
    }

    @Test func mapLinkOnlyForExactPublicPlacesOfOthers() throws {
        let exact = try card(attributes: "{}")
        #expect(PlaceLink.mapURL(for: exact)?.absoluteString
            == "https://www.google.com/maps/search/?api=1&query=43.900000,77.050000")
        #expect(PlaceLink.mapURL(for: try card(attributes: "{}", approximate: true)) == nil)
        #expect(PlaceLink.mapURL(for: try card(attributes: "{}", isOwn: true)) == nil)
        #expect(PlaceLink.mapURL(for: try card(attributes: "{}", visibility: "friends")) == nil)
    }

    @Test func editChangesOnlyWhatChanged() throws {
        let place = try card(attributes: #"{"fee": "free"}"#)
        let original = PlaceEditDraft(place: place)
        var draft = original
        #expect(draft.changes(from: original).isEmpty)

        draft.name = "  Озеро  "
        draft.attributes.fee = .free
        draft.attributes.contact = " "
        #expect(draft.changes(from: original).isEmpty)

        draft.name = "Озеро Большое"
        draft.description = "  Пологий берег "
        draft.attributes.amenities = [.toilet]
        let changes = draft.changes(from: original)
        #expect(changes.name == "Озеро Большое")
        #expect(changes.type == nil)
        #expect(changes.description == "Пологий берег")
        #expect(changes.attributes == PlaceAttributes(fee: .free, amenities: [.toilet]))

        let object = try json(changes)
        #expect(Set(object.keys) == ["name", "description", "attributes"])
        #expect((object["attributes"] as? [String: Any])?.keys.sorted() == ["amenities", "fee"])
    }

    @Test func similarTypes() {
        #expect(PlaceType.fishingSpot.similarTypes.contains(.waterBody))
        #expect(!PlaceType.campsite.similarTypes.contains(.fishingSpot))
        #expect(PlaceType.allCases.allSatisfy { $0.similarTypes.contains($0) })
    }
}
