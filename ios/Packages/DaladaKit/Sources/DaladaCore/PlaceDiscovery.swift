import Foundation

/// Друг, который отмечался в месте (до трёх на карточке).
public struct PlaceFriend: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let username: String?
    public let displayName: String?
    public let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarPath = "avatar_path"
    }

    public init(id: UUID, username: String?, displayName: String?, avatarPath: String?) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarPath = avatarPath
    }

    /// Как подписать: имя, иначе @username.
    public var shortName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return username.map { "@" + $0 } ?? ""
    }
}

/// Место в подборке или результатах поиска — `public.place_item`.
public struct PlaceItem: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let type: PlaceType
    public let name: String
    /// Показанная точка: у чужих приблизительных мест — смещённый центр круга.
    public let coordinate: GeoPoint
    public let isApproximate: Bool
    public let radiusM: Int
    public let visibility: Visibility
    public let isOwn: Bool
    public let isEditorial: Bool
    /// Метры от «моей» точки; `nil` — позиция неизвестна.
    public let distanceM: Int?
    public let ratingAvg: Double?
    public let reviewsCount: Int
    /// Видимые мне отчёты за 30 дней и время последнего.
    public let reports30d: Int
    public let lastReportAt: Date?
    /// Превью последнего видимого фото (путь в бакете `media`).
    public let photoPath: String?
    public let friends: [PlaceFriend]
    public var isSaved: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case lon
        case lat
        case isApproximate = "approximate"
        case radiusM = "radius_m"
        case visibility
        case isOwn = "is_own"
        case isEditorial = "is_editorial"
        case distanceM = "distance_m"
        case ratingAvg = "rating_avg"
        case reviewsCount = "reviews_count"
        case reports30d = "reports_30d"
        case lastReportAt = "last_report_at"
        case photoPath = "photo_path"
        case friends
        case isSaved = "saved"
    }

    public init(
        id: UUID,
        type: PlaceType,
        name: String,
        coordinate: GeoPoint,
        isApproximate: Bool = false,
        radiusM: Int = 0,
        visibility: Visibility = .public,
        isOwn: Bool = false,
        isEditorial: Bool = false,
        distanceM: Int? = nil,
        ratingAvg: Double? = nil,
        reviewsCount: Int = 0,
        reports30d: Int = 0,
        lastReportAt: Date? = nil,
        photoPath: String? = nil,
        friends: [PlaceFriend] = [],
        isSaved: Bool = false
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.coordinate = coordinate
        self.isApproximate = isApproximate
        self.radiusM = radiusM
        self.visibility = visibility
        self.isOwn = isOwn
        self.isEditorial = isEditorial
        self.distanceM = distanceM
        self.ratingAvg = ratingAvg
        self.reviewsCount = reviewsCount
        self.reports30d = reports30d
        self.lastReportAt = lastReportAt
        self.photoPath = photoPath
        self.friends = friends
        self.isSaved = isSaved
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decode(PlaceType.self, forKey: .type)
        name = try c.decode(String.self, forKey: .name)
        coordinate = GeoPoint(
            latitude: try c.decode(Double.self, forKey: .lat),
            longitude: try c.decode(Double.self, forKey: .lon)
        )
        isApproximate = try c.decode(Bool.self, forKey: .isApproximate)
        radiusM = try c.decode(Int.self, forKey: .radiusM)
        visibility = try c.decode(Visibility.self, forKey: .visibility)
        isOwn = try c.decodeIfPresent(Bool.self, forKey: .isOwn) ?? false
        isEditorial = try c.decodeIfPresent(Bool.self, forKey: .isEditorial) ?? false
        distanceM = try c.decodeIfPresent(Int.self, forKey: .distanceM)
        // numeric приходит числом; на всякий случай принимаем и строку.
        if let value = try? c.decodeIfPresent(Double.self, forKey: .ratingAvg) {
            ratingAvg = value
        } else {
            ratingAvg = (try c.decodeIfPresent(String.self, forKey: .ratingAvg)).flatMap(Double.init)
        }
        reviewsCount = try c.decodeIfPresent(Int.self, forKey: .reviewsCount) ?? 0
        reports30d = try c.decodeIfPresent(Int.self, forKey: .reports30d) ?? 0
        lastReportAt = try c.decodeIfPresent(Date.self, forKey: .lastReportAt)
        photoPath = try c.decodeIfPresent(String.self, forKey: .photoPath)
        friends = try c.decodeIfPresent([PlaceFriend].self, forKey: .friends) ?? []
        isSaved = try c.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
    }

    /// В том же виде, что приходит с сервера, — для локального кэша.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(name, forKey: .name)
        try c.encode(coordinate.longitude, forKey: .lon)
        try c.encode(coordinate.latitude, forKey: .lat)
        try c.encode(isApproximate, forKey: .isApproximate)
        try c.encode(radiusM, forKey: .radiusM)
        try c.encode(visibility, forKey: .visibility)
        try c.encode(isOwn, forKey: .isOwn)
        try c.encode(isEditorial, forKey: .isEditorial)
        try c.encodeIfPresent(distanceM, forKey: .distanceM)
        try c.encodeIfPresent(ratingAvg, forKey: .ratingAvg)
        try c.encode(reviewsCount, forKey: .reviewsCount)
        try c.encode(reports30d, forKey: .reports30d)
        try c.encodeIfPresent(lastReportAt, forKey: .lastReportAt)
        try c.encodeIfPresent(photoPath, forKey: .photoPath)
        try c.encode(friends, forKey: .friends)
        try c.encode(isSaved, forKey: .isSaved)
    }
}

/// Подборка редакции: заголовок на трёх языках и места.
public struct PlaceCollection: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let slug: String
    /// `{"ru": …, "kk": …, "en": …}`.
    public let title: [String: String]
    public let places: [PlaceItem]

    public init(id: UUID, slug: String, title: [String: String], places: [PlaceItem]) {
        self.id = id
        self.slug = slug
        self.title = title
        self.places = places
    }

    /// Заголовок на языке интерфейса; нет перевода — русский, затем любой.
    public func title(language: String) -> String {
        title[language] ?? title["ru"] ?? title.values.sorted().first ?? slug
    }
}

/// Подборки вкладки «Места» — ответ `places_discover`.
public struct PlaceDiscovery: Codable, Hashable, Sendable {
    public var nearby: [PlaceItem]
    public var popular: [PlaceItem]
    public var friends: [PlaceItem]
    public var fresh: [PlaceItem]
    public var new: [PlaceItem]
    public var recommended: [PlaceCollection]

    public init(
        nearby: [PlaceItem] = [],
        popular: [PlaceItem] = [],
        friends: [PlaceItem] = [],
        fresh: [PlaceItem] = [],
        new: [PlaceItem] = [],
        recommended: [PlaceCollection] = []
    ) {
        self.nearby = nearby
        self.popular = popular
        self.friends = friends
        self.fresh = fresh
        self.new = new
        self.recommended = recommended
    }

    public func items(_ section: PlaceSection) -> [PlaceItem] {
        switch section {
        case .nearby: nearby
        case .popular: popular
        case .friends: friends
        case .fresh: fresh
        case .new: new
        }
    }

    /// Отметка «сохранено» у места во всех подборках (после нажатия на закладку).
    public mutating func setSaved(_ saved: Bool, placeID: UUID) {
        func update(_ items: inout [PlaceItem]) {
            for index in items.indices where items[index].id == placeID {
                items[index].isSaved = saved
            }
        }
        update(&nearby)
        update(&popular)
        update(&friends)
        update(&fresh)
        update(&new)
        recommended = recommended.map { collection in
            var places = collection.places
            update(&places)
            return PlaceCollection(id: collection.id, slug: collection.slug, title: collection.title, places: places)
        }
    }
}

/// Секция-подборка вкладки «Места» (кроме подборок редакции).
public enum PlaceSection: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case nearby
    case popular
    case friends
    case fresh
    case new

    public var id: String { rawValue }
    public var titleKey: String { "places.section.\(rawValue)" }

    public var systemImage: String {
        switch self {
        case .nearby: "location"
        case .popular: "flame"
        case .friends: "person.2"
        case .fresh: "clock"
        case .new: "sparkles"
        }
    }

    /// Порядок в полном списке («Все»). У «Где были друзья» полного списка нет — только подборка.
    public var fullListSort: PlaceSort? {
        switch self {
        case .nearby: .distance
        case .popular: .popular
        case .fresh: .fresh
        case .new: .new
        case .friends: nil
        }
    }
}

/// Сортировка полного списка и поиска (`places_search.p_sort`).
public enum PlaceSort: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case relevance
    case distance
    case rating
    case fresh
    case popular
    case new
    case name

    public var id: String { rawValue }
    public var titleKey: String { "places.sort.\(rawValue)" }

    /// Какие сортировки предлагать: «по совпадению» — только с запросом, «по расстоянию» — только
    /// когда известна позиция.
    public static func options(hasQuery: Bool, hasLocation: Bool) -> [PlaceSort] {
        allCases.filter { sort in
            switch sort {
            case .relevance: hasQuery
            case .distance: hasLocation
            default: true
            }
        }
    }

    /// Сортировка по умолчанию — как на сервере.
    public static func defaultSort(hasQuery: Bool, hasLocation: Bool) -> PlaceSort {
        if hasQuery { return .relevance }
        return hasLocation ? .distance : .name
    }
}

/// Запрос поиска: текст, типы, сортировка. Пустой — поиск не активен.
public struct PlaceQuery: Hashable, Sendable {
    public var text: String
    public var types: Set<PlaceType>
    public var sort: PlaceSort?

    public init(text: String = "", types: Set<PlaceType> = [], sort: PlaceSort? = nil) {
        self.text = text
        self.types = types
        self.sort = sort
    }

    /// Текст без пробелов по краям и не длиннее, чем принимает сервер (80 символов).
    public var trimmedText: String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    }

    public var isActive: Bool { !trimmedText.isEmpty || !types.isEmpty }
}
