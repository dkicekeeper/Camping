import Foundation
import Testing
@testable import DaladaCore

@Suite("Catch")
struct CatchTests {
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test func decodesPlaceReportWithHiddenSize() throws {
        let json = """
        [{"checkin_id": "cccccccc-0000-0000-0000-000000000001",
          "author_id": "11111111-1111-1111-1111-111111111111",
          "author_username": "arman", "author_display_name": "Арман",
          "at": "2026-09-30T10:00:00Z", "verified": true,
          "conditions": {"bite": "good", "crowd": "few"}, "note": null, "is_own": false,
          "catches": [
            {"id": "dddddddd-0000-0000-0000-000000000001", "species_id": "pike", "count": 2,
             "released": true, "weight_g": null, "length_mm": null}
          ]}]
        """
        let reports = try decoder.decode([PlaceReport].self, from: Data(json.utf8))
        #expect(reports.count == 1)
        let report = reports[0]
        #expect(report.authorUsername == "arman")
        #expect(report.verified)
        #expect(!report.isOwn)
        #expect(report.conditions == CheckinConditions(bite: .good, crowd: .few))
        #expect(report.note == nil)
        #expect(report.catches.first?.speciesID == "pike")
        #expect(report.catches.first?.count == 2)
        #expect(report.catches.first?.weightGrams == nil)
    }

    @Test func decodesMyCatchWithoutPlaceName() throws {
        let json = """
        [{"id": "dddddddd-0000-0000-0000-000000000002", "species_id": "common_carp",
          "weight_g": 3450, "length_mm": 520, "count": 1, "released": false,
          "at": "2026-09-30T10:00:00Z", "visibility": "friends",
          "place_id": "aaaaaaaa-0000-0000-0000-000000000002", "place_name": null}]
        """
        let catches = try decoder.decode([MyCatch].self, from: Data(json.utf8))
        #expect(catches.first?.weightGrams == 3450)
        #expect(catches.first?.visibility == .friends)
        #expect(catches.first?.placeName == nil)
    }

    @Test func unknownConditionValuesAreIgnored() throws {
        let json = #"{"bite": "legendary", "water": "muddy", "wind": "strong"}"#
        let conditions = try JSONDecoder().decode(CheckinConditions.self, from: Data(json.utf8))
        #expect(conditions.bite == nil)
        #expect(conditions.water == .muddy)
        #expect(!conditions.isEmpty)
        #expect(try JSONDecoder().decode(CheckinConditions.self, from: Data("{}".utf8)).isEmpty)
    }

    @Test func emptyConditionsEncodeAsEmptyObject() throws {
        let data = try JSONEncoder().encode(CheckinConditions())
        #expect(String(decoding: data, as: UTF8.self) == "{}")
    }

    @Test func catchDraftConvertsUnits() {
        let draft = CatchDraft(speciesID: "zander", weightKg: 2.35, lengthCm: 61.5)
        #expect(draft.weightGrams == 2350)
        #expect(draft.lengthMillimeters == 615)
        #expect(CatchDraft(speciesID: "zander").weightGrams == nil)
    }

    @Test func catchDraftValidation() {
        var draft = CatchDraft(speciesID: "wels_catfish")
        #expect(draft.isValid)
        draft.weightKg = 0
        #expect(!draft.isValid)
        draft.weightKg = 120
        #expect(draft.isValid)
        draft.weightKg = 201
        #expect(!draft.isValid)
        draft.weightKg = nil
        draft.count = 0
        #expect(!draft.isValid)
    }

    @Test func checkinDraftTrimsNoteAndChecksCatches() {
        var draft = CheckinDraft(placeID: UUID())
        #expect(draft.isValid)
        draft.note = "  клюёт у камыша \n"
        #expect(draft.trimmedNote == "клюёт у камыша")
        draft.catches = [CatchDraft(speciesID: "perch", lengthCm: 400)]
        #expect(!draft.isValid)
    }

    @Test func speciesNameFallsBackToRussian() {
        let species = FishSpecies(id: "pike", nameRu: "Щука", nameKk: "Шортан", nameEn: "Northern pike", nameLatin: "Esox lucius", sortOrder: 60)
        #expect(species.name(for: "kk") == "Шортан")
        #expect(species.name(for: "en") == "Northern pike")
        #expect(species.name(for: "de") == "Щука")
        #expect(species.name(for: nil) == "Щука")
    }
}
