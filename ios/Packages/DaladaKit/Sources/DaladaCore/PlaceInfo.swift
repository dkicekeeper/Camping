import Foundation

// MARK: - «Информация» о месте

/// Атрибуты места (`places.attributes` без служебных `source` и `osm`): то, что не меняется от поездки
/// к поездке. Свежие условия (клёв, вода, людность, дорога) — в отчётах, не здесь.
///
/// Чтение снисходительное: незнакомые значения (редакция могла добавить новые) пропускаются. Запись —
/// только известные ключи и значения, без пустых: так же проверяет база.
public struct PlaceAttributes: Codable, Hashable, Sendable {
    /// Подъезд.
    public enum Access: String, Codable, CaseIterable, Sendable, Identifiable {
        case asphalt, dirt, offroad, foot, boat
        public var id: String { rawValue }
        public var titleKey: String { "place.info.access.\(rawValue)" }
    }

    public enum Fee: String, Codable, CaseIterable, Sendable, Identifiable {
        case free, paid
        public var id: String { rawValue }
        public var titleKey: String { "place.info.fee.\(rawValue)" }
    }

    /// За что цена: вход, сутки, час, килограмм улова.
    public enum PriceUnit: String, Codable, CaseIterable, Sendable, Identifiable {
        case entry, day, hour, kg
        public var id: String { rawValue }
        public var titleKey: String { "place.info.priceUnit.\(rawValue)" }
    }

    /// Способы ловли: откуда (с берега, с лодки) и чем.
    public enum Method: String, Codable, CaseIterable, Sendable, Identifiable {
        case shore, boat, spinning, feeder, float, fly, bottom, ice
        public var id: String { rawValue }
        public var titleKey: String { "place.info.method.\(rawValue)" }
    }

    public enum Amenity: String, Codable, CaseIterable, Sendable, Identifiable {
        case parking, toilet, shade, tent, fireplace
        case drinkingWater = "drinking_water"
        case shop
        case boatRental = "boat_rental"
        public var id: String { rawValue }
        public var titleKey: String { "place.info.amenity.\(rawValue)" }

        public var systemImage: String {
            switch self {
            case .parking: "parkingsign"
            case .toilet: "toilet"
            case .shade: "tree"
            case .tent: "tent"
            case .fireplace: "flame"
            case .drinkingWater: "drop"
            case .shop: "cart"
            case .boatRental: "sailboat"
            }
        }
    }

    /// Мобильная связь.
    public enum Signal: String, Codable, CaseIterable, Sendable, Identifiable {
        case none, weak, good
        public var id: String { rawValue }
        public var titleKey: String { "place.info.signal.\(rawValue)" }
    }

    public static let speciesLimit = 40
    public static let contactLimit = 100
    public static let featuresLimit = 1000
    public static let priceRange = 0...1_000_000

    /// Виды рыбы (id из справочника) в порядке выбора.
    public var species: [String]
    public var access: Set<Access>
    public var fee: Fee?
    /// Цена в тенге — только у платного места.
    public var priceKZT: Int?
    public var priceUnit: PriceUnit?
    public var contact: String?
    public var methods: Set<Method>
    public var amenities: Set<Amenity>
    public var signal: Signal?
    /// Лучшие месяцы, 1–12.
    public var months: Set<Int>
    /// Особенности: глубина, дно, коряги, течение.
    public var features: String?

    public init(
        species: [String] = [],
        access: Set<Access> = [],
        fee: Fee? = nil,
        priceKZT: Int? = nil,
        priceUnit: PriceUnit? = nil,
        contact: String? = nil,
        methods: Set<Method> = [],
        amenities: Set<Amenity> = [],
        signal: Signal? = nil,
        months: Set<Int> = [],
        features: String? = nil
    ) {
        self.species = species
        self.access = access
        self.fee = fee
        self.priceKZT = priceKZT
        self.priceUnit = priceUnit
        self.contact = contact
        self.methods = methods
        self.amenities = amenities
        self.signal = signal
        self.months = months
        self.features = features
    }

    enum CodingKeys: String, CodingKey {
        case species
        case access
        case fee
        case priceKZT = "price_kzt"
        case priceUnit = "price_unit"
        case contact
        case methods
        case amenities
        case signal
        case months
        case features
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func strings(_ key: CodingKeys) -> [String] {
            (try? c.decodeIfPresent([String].self, forKey: key)) ?? []
        }
        func string(_ key: CodingKeys) -> String? {
            (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil
        }
        var seen = Set<String>()
        species = strings(.species).filter { seen.insert($0).inserted }
        access = Set(strings(.access).compactMap(Access.init(rawValue:)))
        fee = string(.fee).flatMap(Fee.init(rawValue:))
        priceKZT = ((try? c.decodeIfPresent(Double.self, forKey: .priceKZT)) ?? nil).flatMap { Int(exactly: $0) }
        priceUnit = string(.priceUnit).flatMap(PriceUnit.init(rawValue:))
        contact = string(.contact)
        methods = Set(strings(.methods).compactMap(Method.init(rawValue:)))
        amenities = Set(strings(.amenities).compactMap(Amenity.init(rawValue:)))
        signal = string(.signal).flatMap(Signal.init(rawValue:))
        months = Set(((try? c.decodeIfPresent([Int].self, forKey: .months)) ?? []).filter { (1...12).contains($0) })
        features = string(.features)
    }

    /// Пишутся только непустые поля, списки — в постоянном порядке.
    public func encode(to encoder: any Encoder) throws {
        let value = normalized
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !value.species.isEmpty { try c.encode(value.species, forKey: .species) }
        if !value.access.isEmpty { try c.encode(Self.ordered(value.access), forKey: .access) }
        try c.encodeIfPresent(value.fee, forKey: .fee)
        try c.encodeIfPresent(value.priceKZT, forKey: .priceKZT)
        try c.encodeIfPresent(value.priceUnit, forKey: .priceUnit)
        try c.encodeIfPresent(value.contact, forKey: .contact)
        if !value.methods.isEmpty { try c.encode(Self.ordered(value.methods), forKey: .methods) }
        if !value.amenities.isEmpty { try c.encode(Self.ordered(value.amenities), forKey: .amenities) }
        try c.encodeIfPresent(value.signal, forKey: .signal)
        if !value.months.isEmpty { try c.encode(value.months.sorted(), forKey: .months) }
        try c.encodeIfPresent(value.features, forKey: .features)
    }

    /// Как запишется в базу: без пробелов по краям, без пустых строк; цена и «за что» — только
    /// у платного места; «за что» — только при цене.
    public var normalized: PlaceAttributes {
        var value = self
        var seen = Set<String>()
        value.species = species.filter { seen.insert($0).inserted }
        value.contact = Self.trimmed(contact)
        value.features = Self.trimmed(features)
        if fee != .paid {
            value.priceKZT = nil
        }
        if value.priceKZT == nil {
            value.priceUnit = nil
        }
        value.months = months.filter { (1...12).contains($0) }
        return value
    }

    public var isEmpty: Bool { normalized == PlaceAttributes() }

    /// Можно отправить: длины и цена в пределах, которые принимает база.
    public var isValid: Bool {
        let value = normalized
        return value.species.count <= Self.speciesLimit
            && (value.contact?.count ?? 0) <= Self.contactLimit
            && (value.features?.count ?? 0) <= Self.featuresLimit
            && value.priceKZT.map(Self.priceRange.contains) ?? true
    }

    /// Месяцы подряд — отрезками «с — по»: [5, 6, 7, 9] → 5–7, 9; через Новый год [11, 12, 1] → 11–1.
    public static func monthSpans(_ months: Set<Int>) -> [MonthSpan] {
        let sorted = months.filter { (1...12).contains($0) }.sorted()
        guard let first = sorted.first else { return [] }
        if sorted.count == 12 { return [MonthSpan(from: 1, to: 12)] }
        var spans = [MonthSpan(from: first, to: first)]
        for month in sorted.dropFirst() {
            if month == spans[spans.count - 1].to + 1 {
                spans[spans.count - 1].to = month
            } else {
                spans.append(MonthSpan(from: month, to: month))
            }
        }
        if spans.count > 1, spans[0].from == 1, spans[spans.count - 1].to == 12 {
            let head = spans.removeFirst()
            spans[spans.count - 1].to = head.to
        }
        return spans
    }

    /// Отрезок месяцев: «с» и «по» (1–12); `from > to` — через Новый год.
    public struct MonthSpan: Equatable, Sendable {
        public var from: Int
        public var to: Int

        public init(from: Int, to: Int) {
            self.from = from
            self.to = to
        }
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func ordered<T: CaseIterable & Equatable>(_ values: Set<T>) -> [T] where T: Hashable {
        T.allCases.filter { values.contains($0) }
    }
}

extension PlaceType {
    /// Похожие типы — для «Рядом» в карточке места: рыбалка, ночёвка, остальное.
    public var similarTypes: Set<PlaceType> {
        switch self {
        case .fishingSpot, .waterBody, .paidPond: [.fishingSpot, .waterBody, .paidPond]
        case .campsite, .base, .parking: [.campsite, .base, .parking]
        case .spring, .landmark: [.spring, .landmark]
        case .tackleShop: [.tackleShop, .paidPond]
        }
    }

    /// Места, где ловят рыбу: у них в «Информации» сначала рыба и способы ловли.
    public var isFishing: Bool {
        [.fishingSpot, .waterBody, .paidPond].contains(self)
    }
}

// MARK: - Сводка отчётов

/// «За 7 дней: 12 отчётов, клёв в основном хороший» — по загруженным отчётам места.
public struct PlaceReportsSummary: Equatable, Sendable {
    public static let days = 7

    /// Отчётов за 7 дней.
    public let count: Int
    /// Загружены не все отчёты за 7 дней — показываем «N+».
    public let isLowerBound: Bool
    /// Чаще всего отмеченный клёв; при равенстве — тот, что отмечен позже.
    public let bite: CheckinConditions.Bite?

    public init(count: Int, isLowerBound: Bool, bite: CheckinConditions.Bite?) {
        self.count = count
        self.isLowerBound = isLowerBound
        self.bite = bite
    }

    /// `nil` — за 7 дней отчётов нет. `limit` — сколько отчётов запрашивали.
    public static func make(_ reports: [PlaceReport], limit: Int, now: Date = Date()) -> PlaceReportsSummary? {
        make(entries: reports.map { (at: $0.at, bite: $0.conditions.bite) }, limit: limit, now: now)
    }

    static func make(
        entries: [(at: Date, bite: CheckinConditions.Bite?)],
        limit: Int,
        now: Date
    ) -> PlaceReportsSummary? {
        let since = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        let recent = entries.filter { $0.at > since }.sorted { $0.at > $1.at }
        guard !recent.isEmpty else { return nil }
        // Все загруженные — свежие, а загружено столько, сколько просили: за неделю их может быть больше.
        let isLowerBound = entries.count >= limit && recent.count == entries.count

        var counts: [CheckinConditions.Bite: Int] = [:]
        var latest: [CheckinConditions.Bite: Date] = [:]
        for entry in recent {
            guard let bite = entry.bite else { continue }
            counts[bite, default: 0] += 1
            latest[bite] = max(latest[bite] ?? .distantPast, entry.at)
        }
        let bite = counts.max { a, b in
            a.value != b.value ? a.value < b.value : (latest[a.key] ?? .distantPast) < (latest[b.key] ?? .distantPast)
        }?.key
        return PlaceReportsSummary(count: recent.count, isLowerBound: isLowerBound, bite: bite)
    }
}

// MARK: - Ссылка на место

/// Ссылка на место: `dalada://place/<id>` («Поделиться»). Откроется у того, кому место видно.
public enum PlaceLink {
    static let host = "place"

    public static func url(placeID: UUID) -> URL {
        URL(string: "\(InviteLink.scheme)://\(host)/\(placeID.uuidString.lowercased())")!
    }

    public static func placeID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == InviteLink.scheme, url.host?.lowercased() == host else { return nil }
        return url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
    }

    /// Точка на карте для тех, у кого нет приложения, — только у чужого публичного места с точной
    /// точкой. Своё место может быть показано другим приблизительно: его точку не раскрываем.
    public static func mapURL(for place: PlaceDetails) -> URL? {
        guard place.visibility == .public, place.status == .published, !place.isApproximate, !place.isOwn
        else { return nil }
        let lat = Navigator.coordinate(place.coordinate.latitude)
        let lon = Navigator.coordinate(place.coordinate.longitude)
        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lon)")
    }
}

// MARK: - Правка места

/// Что можно сообщить о чужом публичном месте (`public.place_suggestion_kind`).
public enum PlaceSuggestionKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case edit
    case wrongLocation = "wrong_location"
    case closed
    case notExists = "not_exists"
    case duplicate
    case dangerous

    public var id: String { rawValue }
    public var titleKey: String { "place.suggest.kind.\(rawValue)" }

    /// «Сообщить о проблеме» — всё, кроме правки полей.
    public static var problems: [PlaceSuggestionKind] { allCases.filter { $0 != .edit } }
}

/// Поля места, которые можно изменить: своё место — сразу, чужое — предложением правки.
public struct PlaceEditDraft: Equatable, Sendable {
    public static let noteLimit = 1000

    public var type: PlaceType
    public var name: String
    public var description: String
    public var attributes: PlaceAttributes

    public init(type: PlaceType, name: String, description: String, attributes: PlaceAttributes) {
        self.type = type
        self.name = name
        self.description = description
        self.attributes = attributes
    }

    public init(place: PlaceDetails) {
        self.init(type: place.type, name: place.name, description: place.description ?? "", attributes: place.info)
    }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isValid: Bool {
        (1...PlaceDraft.nameLimit).contains(trimmedName.count)
            && trimmedDescription.count <= PlaceDraft.descriptionLimit
            && attributes.isValid
    }

    /// Изменения относительно исходных значений — только отличающиеся поля.
    public func changes(from original: PlaceEditDraft) -> PlaceChanges {
        PlaceChanges(
            name: trimmedName != original.trimmedName ? trimmedName : nil,
            type: type != original.type ? type : nil,
            description: trimmedDescription != original.trimmedDescription ? trimmedDescription : nil,
            attributes: attributes.normalized != original.attributes.normalized ? attributes.normalized : nil
        )
    }
}

/// Предложенные изменения (`place_suggestions.changes`): только заданные поля. Пустое описание —
/// «убрать описание».
public struct PlaceChanges: Encodable, Equatable, Sendable {
    public var name: String?
    public var type: PlaceType?
    public var description: String?
    public var attributes: PlaceAttributes?

    public init(name: String? = nil, type: PlaceType? = nil, description: String? = nil, attributes: PlaceAttributes? = nil) {
        self.name = name
        self.type = type
        self.description = description
        self.attributes = attributes
    }

    public var isEmpty: Bool { name == nil && type == nil && description == nil && attributes == nil }
}

/// Своё место для правки — строка `places` (свои строки читаются напрямую): поля и видимость.
public struct OwnPlaceDraft: Decodable, Equatable, Sendable {
    public var fields: PlaceEditDraft
    public var visibility: Visibility
    /// Показывать другим кругом ~1 км. Для «только я» не имеет смысла.
    public var isApproximate: Bool

    public init(fields: PlaceEditDraft, visibility: Visibility, isApproximate: Bool) {
        self.fields = fields
        self.visibility = visibility
        self.isApproximate = isApproximate
    }

    enum CodingKeys: String, CodingKey {
        case type
        case name
        case description
        case visibility
        case approximate
        case attributes
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fields = PlaceEditDraft(
            type: try c.decode(PlaceType.self, forKey: .type),
            name: try c.decode(String.self, forKey: .name),
            description: try c.decodeIfPresent(String.self, forKey: .description) ?? "",
            attributes: (try? c.decodeIfPresent(PlaceAttributes.self, forKey: .attributes)) ?? PlaceAttributes()
        )
        visibility = try c.decode(Visibility.self, forKey: .visibility)
        isApproximate = try c.decode(Bool.self, forKey: .approximate)
    }

    /// Флаг, который уйдёт в базу: для приватных мест огрубление не нужно.
    public var effectiveApproximate: Bool { visibility != .private && isApproximate }

    public var isValid: Bool { fields.isValid }
}
