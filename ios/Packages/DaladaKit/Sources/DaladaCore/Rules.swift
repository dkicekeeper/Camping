import Foundation

// MARK: - Тексты на трёх языках

/// Текст на русском, казахском и английском (справочник правил).
public struct LocalizedText: Codable, Hashable, Sendable {
    public let ru: String
    public let kk: String
    public let en: String

    public init(ru: String, kk: String, en: String) {
        self.ru = ru
        self.kk = kk
        self.en = en
    }

    /// Текст на языке `code` ("ru", "kk", "en"); незнакомый язык — русский.
    public func text(for code: String) -> String {
        switch code {
        case "kk": kk.isEmpty ? ru : kk
        case "en": en.isEmpty ? ru : en
        default: ru
        }
    }
}

// MARK: - Календарь

extension CalendarDay {
    /// Номер дня от 1 января 1970 года (григорианский календарь) — для разницы в днях.
    public var ordinal: Int {
        // Howard Hinnant, days_from_civil.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let m = month
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Сколько дней до `other` (отрицательное — `other` раньше).
    public func days(until other: CalendarDay) -> Int {
        other.ordinal - ordinal
    }

    public static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// День в году `year`; 29 февраля в невисокосный год — 28 февраля.
    static func clamped(year: Int, month: Int, day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: min(day, daysIn(month: month, year: year)))
    }
}

/// Ежегодный срок «с (месяц, день) по (месяц, день)» включительно. Может переходить через Новый год.
public struct YearlyWindow: Hashable, Sendable {
    public let startMonth: Int
    public let startDay: Int
    public let endMonth: Int
    public let endDay: Int

    public init(startMonth: Int, startDay: Int, endMonth: Int, endDay: Int) {
        self.startMonth = startMonth
        self.startDay = startDay
        self.endMonth = endMonth
        self.endDay = endDay
    }

    /// Период, который идёт в день `day` или начнётся следующим (как `private.rule_period` в базе).
    public func period(around day: CalendarDay) -> ClosedRange<CalendarDay> {
        let y = day.year
        var start = CalendarDay.clamped(year: y, month: startMonth, day: startDay)
        var end = CalendarDay.clamped(year: y, month: endMonth, day: endDay)
        if start <= end {
            if day > end {
                start = CalendarDay.clamped(year: y + 1, month: startMonth, day: startDay)
                end = CalendarDay.clamped(year: y + 1, month: endMonth, day: endDay)
            }
        } else if day <= end {
            start = CalendarDay.clamped(year: y - 1, month: startMonth, day: startDay)
        } else {
            end = CalendarDay.clamped(year: y + 1, month: endMonth, day: endDay)
        }
        return start...end
    }
}

// MARK: - Зоны

/// Многоугольник: внешний контур и отверстия (точки — долгота/широта).
public struct GeoPolygon: Hashable, Sendable {
    public let rings: [[GeoPoint]]

    public init(rings: [[GeoPoint]]) {
        self.rings = rings
    }

    /// Точка внутри (правило чёт-нечет по всем контурам — отверстия исключаются сами).
    public func contains(_ point: GeoPoint) -> Bool {
        var inside = false
        for ring in rings where ring.count >= 3 {
            var j = ring.count - 1
            for i in 0..<ring.count {
                let a = ring[i]
                let b = ring[j]
                if (a.latitude > point.latitude) != (b.latitude > point.latitude) {
                    let x = (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude
                    if point.longitude < x {
                        inside.toggle()
                    }
                }
                j = i
            }
        }
        return inside
    }

    var bounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        guard let outer = rings.first, !outer.isEmpty else { return nil }
        let lats = outer.map(\.latitude)
        let lons = outer.map(\.longitude)
        return (lats.min()!, lats.max()!, lons.min()!, lons.max()!)
    }
}

public enum RuleZoneKind: String, Codable, Sendable {
    case reservoir
    case lake
    case river
    case delta
    case restZone = "rest_zone"
}

/// Зона правил — строка `rule_zones`. Граница приблизительная (OpenStreetMap).
public struct RuleZone: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: RuleZoneKind
    public let basin: String
    public let name: LocalizedText
    public let note: LocalizedText?
    public let polygons: [GeoPolygon]
    public let sortOrder: Int

    public init(
        id: String,
        kind: RuleZoneKind,
        basin: String = "balkhash_alakol",
        name: LocalizedText,
        note: LocalizedText? = nil,
        polygons: [GeoPolygon],
        sortOrder: Int = 100
    ) {
        self.id = id
        self.kind = kind
        self.basin = basin
        self.name = name
        self.note = note
        self.polygons = polygons
        self.sortOrder = sortOrder
    }

    public func contains(_ point: GeoPoint) -> Bool {
        polygons.contains { polygon in
            guard let b = polygon.bounds,
                  (b.minLat...b.maxLat).contains(point.latitude),
                  (b.minLon...b.maxLon).contains(point.longitude)
            else { return false }
            return polygon.contains(point)
        }
    }

    /// Все точки внешних контуров — для рамки карты.
    public var outline: [GeoPoint] { polygons.compactMap(\.rings.first).flatMap { $0 } }

    enum CodingKeys: String, CodingKey {
        case id, kind, basin
        case nameRU = "name_ru", nameKK = "name_kk", nameEN = "name_en"
        case noteRU = "note_ru", noteKK = "note_kk", noteEN = "note_en"
        case geom
        case sortOrder = "sort_order"
    }

    /// GeoJSON `MultiPolygon` из PostgREST.
    struct MultiPolygon: Codable {
        var type = "MultiPolygon"
        var coordinates: [[[[Double]]]]
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(RuleZoneKind.self, forKey: .kind)
        basin = try c.decodeIfPresent(String.self, forKey: .basin) ?? ""
        name = LocalizedText(
            ru: try c.decode(String.self, forKey: .nameRU),
            kk: try c.decodeIfPresent(String.self, forKey: .nameKK) ?? "",
            en: try c.decodeIfPresent(String.self, forKey: .nameEN) ?? ""
        )
        if let ru = try c.decodeIfPresent(String.self, forKey: .noteRU) {
            note = LocalizedText(
                ru: ru,
                kk: try c.decodeIfPresent(String.self, forKey: .noteKK) ?? "",
                en: try c.decodeIfPresent(String.self, forKey: .noteEN) ?? ""
            )
        } else {
            note = nil
        }
        let geometry = try? c.decodeIfPresent(MultiPolygon.self, forKey: .geom)
        polygons = (geometry?.coordinates ?? []).map { polygon in
            GeoPolygon(rings: polygon.map { ring in
                ring.compactMap { position in
                    position.count >= 2 ? GeoPoint(latitude: position[1], longitude: position[0]) : nil
                }
            })
        }
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 100
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(basin, forKey: .basin)
        try c.encode(name.ru, forKey: .nameRU)
        try c.encode(name.kk, forKey: .nameKK)
        try c.encode(name.en, forKey: .nameEN)
        try c.encodeIfPresent(note?.ru, forKey: .noteRU)
        try c.encodeIfPresent(note?.kk, forKey: .noteKK)
        try c.encodeIfPresent(note?.en, forKey: .noteEN)
        let coordinates = polygons.map { polygon in
            polygon.rings.map { ring in ring.map { [$0.longitude, $0.latitude] } }
        }
        try c.encode(polygons.isEmpty ? nil : MultiPolygon(coordinates: coordinates), forKey: .geom)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

// MARK: - Правила

public enum RegulationKind: String, Codable, Sendable {
    case fishingBan = "fishing_ban"
    case minSize = "min_size"
    case methodBan = "method_ban"
    case info
}

/// Кого касается запрет: любое рыболовство или любительские (непромысловые) орудия.
public enum RegulationGear: String, Codable, Sendable {
    case all
    case amateur
}

/// Правило — строка `regulations`.
public struct Regulation: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: RegulationKind
    /// Зоны; пусто — общее правило для всех водоёмов.
    public let zoneIDs: [String]
    public let gear: RegulationGear
    /// Ежегодный срок; `nil` — круглый год.
    public let window: YearlyWindow?
    /// Промысловая мера: вид (`FishSpecies.id`) → см.
    public let minSizes: [String: Int]
    public let title: LocalizedText
    public let body: LocalizedText
    public let sourceTitle: String
    public let sourceURL: URL?
    public let sourceClause: String
    public let verifiedOn: CalendarDay?
    public let sortOrder: Int

    public init(
        id: String,
        kind: RegulationKind,
        zoneIDs: [String],
        gear: RegulationGear = .all,
        window: YearlyWindow?,
        minSizes: [String: Int] = [:],
        title: LocalizedText,
        body: LocalizedText,
        sourceTitle: String = "",
        sourceURL: URL? = nil,
        sourceClause: String = "",
        verifiedOn: CalendarDay? = nil,
        sortOrder: Int = 100
    ) {
        self.id = id
        self.kind = kind
        self.zoneIDs = zoneIDs
        self.gear = gear
        self.window = window
        self.minSizes = minSizes
        self.title = title
        self.body = body
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
        self.sourceClause = sourceClause
        self.verifiedOn = verifiedOn
        self.sortOrder = sortOrder
    }

    public var isGeneral: Bool { zoneIDs.isEmpty }

    enum CodingKeys: String, CodingKey {
        case id, kind, gear
        case zoneIDs = "zone_ids"
        case startMonth = "start_month", startDay = "start_day", endMonth = "end_month", endDay = "end_day"
        case minSizes = "min_sizes"
        case titleRU = "title_ru", titleKK = "title_kk", titleEN = "title_en"
        case bodyRU = "body_ru", bodyKK = "body_kk", bodyEN = "body_en"
        case sourceTitle = "source_title"
        case sourceURL = "source_url"
        case sourceClause = "source_clause"
        case verifiedOn = "verified_on"
        case sortOrder = "sort_order"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = (try? c.decode(RegulationKind.self, forKey: .kind)) ?? .info
        zoneIDs = try c.decodeIfPresent([String].self, forKey: .zoneIDs) ?? []
        gear = (try? c.decode(RegulationGear.self, forKey: .gear)) ?? .all
        if let sm = try c.decodeIfPresent(Int.self, forKey: .startMonth),
           let sd = try c.decodeIfPresent(Int.self, forKey: .startDay),
           let em = try c.decodeIfPresent(Int.self, forKey: .endMonth),
           let ed = try c.decodeIfPresent(Int.self, forKey: .endDay) {
            window = YearlyWindow(startMonth: sm, startDay: sd, endMonth: em, endDay: ed)
        } else {
            window = nil
        }
        minSizes = try c.decodeIfPresent([String: Int].self, forKey: .minSizes) ?? [:]
        title = LocalizedText(
            ru: try c.decode(String.self, forKey: .titleRU),
            kk: try c.decodeIfPresent(String.self, forKey: .titleKK) ?? "",
            en: try c.decodeIfPresent(String.self, forKey: .titleEN) ?? ""
        )
        body = LocalizedText(
            ru: try c.decode(String.self, forKey: .bodyRU),
            kk: try c.decodeIfPresent(String.self, forKey: .bodyKK) ?? "",
            en: try c.decodeIfPresent(String.self, forKey: .bodyEN) ?? ""
        )
        sourceTitle = try c.decodeIfPresent(String.self, forKey: .sourceTitle) ?? ""
        sourceURL = (try c.decodeIfPresent(String.self, forKey: .sourceURL)).flatMap(URL.init(string:))
        sourceClause = try c.decodeIfPresent(String.self, forKey: .sourceClause) ?? ""
        verifiedOn = try c.decodeIfPresent(CalendarDay.self, forKey: .verifiedOn)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 100
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(zoneIDs, forKey: .zoneIDs)
        try c.encode(gear, forKey: .gear)
        try c.encodeIfPresent(window?.startMonth, forKey: .startMonth)
        try c.encodeIfPresent(window?.startDay, forKey: .startDay)
        try c.encodeIfPresent(window?.endMonth, forKey: .endMonth)
        try c.encodeIfPresent(window?.endDay, forKey: .endDay)
        try c.encode(minSizes.isEmpty ? nil : minSizes, forKey: .minSizes)
        try c.encode(title.ru, forKey: .titleRU)
        try c.encode(title.kk, forKey: .titleKK)
        try c.encode(title.en, forKey: .titleEN)
        try c.encode(body.ru, forKey: .bodyRU)
        try c.encode(body.kk, forKey: .bodyKK)
        try c.encode(body.en, forKey: .bodyEN)
        try c.encode(sourceTitle, forKey: .sourceTitle)
        try c.encodeIfPresent(sourceURL?.absoluteString, forKey: .sourceURL)
        try c.encode(sourceClause, forKey: .sourceClause)
        try c.encodeIfPresent(verifiedOn, forKey: .verifiedOn)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

/// Состояние срочного правила на день.
public enum RuleStatus: Hashable, Sendable {
    /// Круглый год.
    case yearRound
    /// Идёт сейчас, до `end` включительно.
    case active(end: CalendarDay)
    /// Начнётся через `days` дней (в пределах «скоро»).
    case soon(start: CalendarDay, end: CalendarDay, days: Int)
    /// Следующий период — позже.
    case later(start: CalendarDay, end: CalendarDay)

    /// Действует в этот день.
    public var isInForce: Bool {
        switch self {
        case .yearRound, .active: true
        case .soon, .later: false
        }
    }
}

// MARK: - Пакет правил

/// Все зоны и правила бассейна — работают без сети (кэш на телефоне).
public struct RulesPack: Codable, Hashable, Sendable {
    /// «Скоро» — начнётся в ближайшие столько дней.
    public static let soonDays = 30

    public let zones: [RuleZone]
    public let regulations: [Regulation]

    public init(zones: [RuleZone], regulations: [Regulation]) {
        self.zones = zones.sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) }
        self.regulations = regulations.sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) }
    }

    public var isEmpty: Bool { zones.isEmpty && regulations.isEmpty }

    public func zone(_ id: String) -> RuleZone? {
        zones.first { $0.id == id }
    }

    public func zones(containing point: GeoPoint) -> [RuleZone] {
        zones.filter { $0.contains(point) }
    }

    /// Правила зоны.
    public func regulations(inZone id: String) -> [Regulation] {
        regulations.filter { $0.zoneIDs.contains(id) }
    }

    public var generalRegulations: [Regulation] {
        regulations.filter(\.isGeneral)
    }

    /// Правила зон, в которые попала точка (без общих).
    public func regulations(at point: GeoPoint) -> [Regulation] {
        let here = Set(zones(containing: point).map(\.id))
        guard !here.isEmpty else { return [] }
        return regulations.filter { !$0.isGeneral && !here.isDisjoint(with: $0.zoneIDs) }
    }

    /// Промысловая мера вида в точке, см.
    public func minSize(of speciesID: String, at point: GeoPoint) -> Int? {
        regulations(at: point).compactMap { $0.minSizes[speciesID] }.max()
    }

    /// Все промысловые меры в точке: вид → см.
    public func minSizes(at point: GeoPoint) -> [String: Int] {
        regulations(at: point).reduce(into: [:]) { result, regulation in
            result.merge(regulation.minSizes) { max($0, $1) }
        }
    }

    public func status(of regulation: Regulation, on day: CalendarDay) -> RuleStatus {
        guard let window = regulation.window else { return .yearRound }
        let period = window.period(around: day)
        if period.contains(day) {
            return .active(end: period.upperBound)
        }
        let days = day.days(until: period.lowerBound)
        if days <= Self.soonDays {
            return .soon(start: period.lowerBound, end: period.upperBound, days: days)
        }
        return .later(start: period.lowerBound, end: period.upperBound)
    }

    /// Запреты, которые действуют в точке в этот день.
    public func activeBans(at point: GeoPoint, on day: CalendarDay) -> [Regulation] {
        regulations(at: point).filter { $0.kind == .fishingBan && status(of: $0, on: day).isInForce }
    }

    /// Запреты в точке, которые начнутся скоро.
    public func upcomingBans(at point: GeoPoint, on day: CalendarDay) -> [Regulation] {
        regulations(at: point).filter { regulation in
            guard regulation.kind == .fishingBan, case .soon = status(of: regulation, on: day) else { return false }
            return true
        }
    }

    /// Самое строгое состояние запретов зоны на день: для цвета на карте.
    public func banState(ofZone id: String, on day: CalendarDay) -> ZoneBanState {
        let statuses = regulations(inZone: id).filter { $0.kind == .fishingBan }.map { status(of: $0, on: day) }
        if statuses.contains(where: \.isInForce) { return .active }
        if statuses.contains(where: { if case .soon = $0 { true } else { false } }) { return .soon }
        return .none
    }
}

/// Цвет зоны на карте.
public enum ZoneBanState: String, Hashable, Sendable {
    case active
    case soon
    case none
}

/// Элемент списка, который пропускается, если не разобрался (например, зона незнакомого вида из
/// новой версии сервера) — вместо ошибки всего списка.
public struct Lenient<Value: Decodable>: Decodable {
    public let value: Value?

    public init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension Lenient: Sendable where Value: Sendable {}
