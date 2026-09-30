import Foundation
import Testing
@testable import DaladaCore

@Suite("Rules")
struct RulesTests {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d) }

    private func square(_ minLon: Double, _ minLat: Double, _ maxLon: Double, _ maxLat: Double) -> [GeoPoint] {
        [
            GeoPoint(latitude: minLat, longitude: minLon),
            GeoPoint(latitude: minLat, longitude: maxLon),
            GeoPoint(latitude: maxLat, longitude: maxLon),
            GeoPoint(latitude: maxLat, longitude: minLon),
            GeoPoint(latitude: minLat, longitude: minLon),
        ]
    }

    private var text: LocalizedText { LocalizedText(ru: "Запрет", kk: "Тыйым", en: "Ban") }

    private var pack: RulesPack {
        let lake = RuleZone(
            id: "lake", kind: .reservoir, name: LocalizedText(ru: "Озеро", kk: "Көл", en: "Lake"),
            polygons: [GeoPolygon(rings: [square(77, 43, 78, 44), square(77.4, 43.4, 77.6, 43.6)])]
        )
        let river = RuleZone(
            id: "river", kind: .river, name: LocalizedText(ru: "Река", kk: "Өзен", en: "River"),
            polygons: [GeoPolygon(rings: [square(77.9, 43.9, 79, 44.1)])]
        )
        return RulesPack(zones: [river, lake], regulations: [
            Regulation(id: "spawning", kind: .fishingBan, zoneIDs: ["lake"],
                       window: YearlyWindow(startMonth: 4, startDay: 5, endMonth: 5, endDay: 20),
                       title: text, body: text, sortOrder: 10),
            Regulation(id: "rest", kind: .fishingBan, zoneIDs: ["river"], window: nil,
                       title: text, body: text, sortOrder: 20),
            Regulation(id: "sizes_lake", kind: .minSize, zoneIDs: ["lake"], window: nil,
                       minSizes: ["common_carp": 40, "zander": 38], title: text, body: text, sortOrder: 30),
            Regulation(id: "sizes_river", kind: .minSize, zoneIDs: ["river"], window: nil,
                       minSizes: ["common_carp": 43], title: text, body: text, sortOrder: 40),
            Regulation(id: "methods", kind: .methodBan, zoneIDs: [], window: nil,
                       title: text, body: text, sortOrder: 50),
        ])
    }

    @Test func pointInPolygonRespectsHoles() {
        let polygon = GeoPolygon(rings: [square(77, 43, 78, 44), square(77.4, 43.4, 77.6, 43.6)])
        #expect(polygon.contains(GeoPoint(latitude: 43.2, longitude: 77.2)))
        #expect(!polygon.contains(GeoPoint(latitude: 43.5, longitude: 77.5)), "в отверстии — не внутри")
        #expect(!polygon.contains(GeoPoint(latitude: 44.5, longitude: 77.5)))
    }

    @Test func yearlyWindowPeriods() {
        let spring = YearlyWindow(startMonth: 4, startDay: 5, endMonth: 5, endDay: 20)
        #expect(spring.period(around: day(2027, 4, 10)) == day(2027, 4, 5)...day(2027, 5, 20))
        #expect(spring.period(around: day(2027, 1, 1)) == day(2027, 4, 5)...day(2027, 5, 20))
        #expect(spring.period(around: day(2027, 6, 1)) == day(2028, 4, 5)...day(2028, 5, 20))

        let winter = YearlyWindow(startMonth: 12, startDay: 1, endMonth: 2, endDay: 28)
        #expect(winter.period(around: day(2027, 1, 15)) == day(2026, 12, 1)...day(2027, 2, 28))
        #expect(winter.period(around: day(2027, 6, 1)) == day(2027, 12, 1)...day(2028, 2, 28))

        let leap = YearlyWindow(startMonth: 2, startDay: 29, endMonth: 3, endDay: 10)
        #expect(leap.period(around: day(2027, 1, 1)).lowerBound == day(2027, 2, 28))
        #expect(leap.period(around: day(2028, 1, 1)).lowerBound == day(2028, 2, 29))
    }

    @Test func dayArithmetic() {
        #expect(day(1970, 1, 1).ordinal == 0)
        #expect(day(2027, 3, 1).days(until: day(2027, 4, 5)) == 35)
        #expect(day(2028, 2, 28).days(until: day(2028, 3, 1)) == 2, "2028 — високосный")
        #expect(day(2027, 12, 31).days(until: day(2028, 1, 1)) == 1)
    }

    @Test func statusesOnDates() {
        let pack = pack
        let spawning = pack.regulations.first { $0.id == "spawning" }!
        let rest = pack.regulations.first { $0.id == "rest" }!
        #expect(pack.status(of: rest, on: day(2027, 9, 1)) == .yearRound)
        #expect(pack.status(of: spawning, on: day(2027, 4, 10)) == .active(end: day(2027, 5, 20)))
        #expect(pack.status(of: spawning, on: day(2027, 3, 20)) == .soon(start: day(2027, 4, 5), end: day(2027, 5, 20), days: 16))
        #expect(pack.status(of: spawning, on: day(2027, 6, 1)) == .later(start: day(2028, 4, 5), end: day(2028, 5, 20)))
        #expect(pack.status(of: spawning, on: day(2027, 5, 20)).isInForce, "последний день включительно")
    }

    @Test func rulesAtPoint() {
        let pack = pack
        let inLake = GeoPoint(latitude: 43.2, longitude: 77.2)
        let inRiver = GeoPoint(latitude: 44.0, longitude: 78.5)
        let overlap = GeoPoint(latitude: 43.95, longitude: 77.95)
        let almaty = GeoPoint(latitude: 43.25, longitude: 76.9)

        #expect(pack.regulations(at: inLake).map(\.id) == ["spawning", "sizes_lake"])
        #expect(pack.regulations(at: almaty).isEmpty, "общие правила — отдельно")
        #expect(pack.generalRegulations.map(\.id) == ["methods"])
        #expect(pack.activeBans(at: inLake, on: day(2027, 4, 10)).map(\.id) == ["spawning"])
        #expect(pack.activeBans(at: inLake, on: day(2027, 7, 1)).isEmpty)
        #expect(pack.upcomingBans(at: inLake, on: day(2027, 3, 20)).map(\.id) == ["spawning"])
        #expect(pack.activeBans(at: inRiver, on: day(2027, 7, 1)).map(\.id) == ["rest"])
        #expect(pack.minSize(of: "common_carp", at: inLake) == 40)
        #expect(pack.minSize(of: "common_carp", at: overlap) == 43, "на стыке зон — строже")
        #expect(pack.minSize(of: "bream", at: inLake) == nil)
        #expect(pack.minSizes(at: inLake) == ["common_carp": 40, "zander": 38])
        #expect(pack.zones.map(\.id) == ["lake", "river"], "по sort_order, при равенстве — по id")
    }

    @Test func zoneBanStateForMap() {
        let pack = pack
        #expect(pack.banState(ofZone: "lake", on: day(2027, 4, 10)) == .active)
        #expect(pack.banState(ofZone: "lake", on: day(2027, 3, 20)) == .soon)
        #expect(pack.banState(ofZone: "lake", on: day(2027, 8, 1)) == .none)
        #expect(pack.banState(ofZone: "river", on: day(2027, 8, 1)) == .active)
    }

    @Test func decodesServerRowsAndCaches() throws {
        let zonesJSON = """
        [{"id": "zhalanashkol", "kind": "lake", "basin": "balkhash_alakol", "name_ru": "Озеро Жаланашколь",
          "name_kk": "Жалаңашкөл көлі", "name_en": "Lake Zhalanashkol", "note_ru": null, "note_kk": null, "note_en": null,
          "geom": {"type": "MultiPolygon", "coordinates": [[[[82.1, 45.5], [82.2, 45.5], [82.2, 45.6], [82.1, 45.6], [82.1, 45.5]]]]},
          "sort_order": 100},
         {"id": "future", "kind": "canal", "basin": "x", "name_ru": "Канал", "geom": null}]
        """
        let regulationsJSON = """
        [{"id": "kapshagay_spawning", "kind": "fishing_ban", "basin": "balkhash_alakol", "zone_ids": ["kapshagay"],
          "gear": "all", "start_month": 4, "start_day": 5, "end_month": 5, "end_day": 20, "min_sizes": null,
          "title_ru": "Нерестовый запрет", "title_kk": "Тыйым", "title_en": "Spawning ban",
          "body_ru": "Текст", "body_kk": "Мәтін", "body_en": "Text",
          "source_title": "Приказ № 78", "source_url": "https://adilet.zan.kz/rus/docs/V2600038112",
          "source_clause": "прил. 1, п. 7, пп. 3", "verified_on": "2026-09-30", "sort_order": 10},
         {"id": "min_size_alakol", "kind": "min_size", "basin": "balkhash_alakol", "zone_ids": ["alakol_lakes"],
          "gear": "all", "start_month": null, "start_day": null, "end_month": null, "end_day": null,
          "min_sizes": {"zander": 37, "common_carp": 43},
          "title_ru": "Промысловая мера", "title_kk": "", "title_en": "Minimum size",
          "body_ru": "Текст", "body_kk": "", "body_en": "Text", "source_title": "Правила",
          "source_url": "https://adilet.zan.kz/rus/docs/V1500010606", "source_clause": "п. 3",
          "verified_on": "2026-09-30", "sort_order": 220}]
        """
        let zones = try JSONDecoder().decode([Lenient<RuleZone>].self, from: Data(zonesJSON.utf8)).compactMap(\.value)
        #expect(zones.count == 1, "зона незнакомого вида пропускается")
        #expect(zones[0].contains(GeoPoint(latitude: 45.55, longitude: 82.15)))
        let regulations = try JSONDecoder().decode([Regulation].self, from: Data(regulationsJSON.utf8))
        #expect(regulations[0].window == YearlyWindow(startMonth: 4, startDay: 5, endMonth: 5, endDay: 20))
        #expect(regulations[0].verifiedOn == day(2026, 9, 30))
        #expect(regulations[1].window == nil)
        #expect(regulations[1].minSizes == ["zander": 37, "common_carp": 43])
        #expect(regulations[1].title.text(for: "kk") == "Промысловая мера", "пустой перевод — русский")

        let pack = RulesPack(zones: zones, regulations: regulations)
        let cached = try JSONDecoder().decode(RulesPack.self, from: JSONEncoder().encode(pack))
        #expect(cached == pack)
    }
}
