import Foundation

// MARK: - Профиль другого человека

/// Итоги человека по тому, что видит зритель, — строка `user_stats`.
public struct UserPublicStats: Codable, Equatable, Sendable {
    public let tripsCount: Int
    public let distanceM: Int
    public let placesCount: Int
    public let catchesCount: Int
    public let friendsCount: Int

    enum CodingKeys: String, CodingKey {
        case tripsCount = "trips_count"
        case distanceM = "distance_m"
        case placesCount = "places_count"
        case catchesCount = "catches_count"
        case friendsCount = "friends_count"
    }
}

// MARK: - Лента друзей

/// Автор записи в ленте.
public struct FeedAuthor: Codable, Hashable, Sendable {
    public let id: UUID
    public let username: String?
    public let displayName: String?
    public let avatarPath: String?

    public init(id: UUID, username: String?, displayName: String?, avatarPath: String? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarPath = avatarPath
    }
}

/// Поездка друга в ленте (без трека: он — на странице поездки).
public struct FeedTrip: Codable, Hashable, Sendable {
    public let activity: TripActivity
    public let title: String
    public let note: String?
    public let startedAt: Date
    public let endedAt: Date
    public let movingSeconds: Int
    public let distanceM: Int
    public let elevationGainM: Int

    enum CodingKeys: String, CodingKey {
        case activity
        case title
        case note
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case movingSeconds = "moving_seconds"
        case distanceM = "distance_m"
        case elevationGainM = "elevation_gain_m"
    }
}

/// Чекин-отчёт друга в ленте: место, условия, заметка, уловы, фото.
public struct FeedCheckin: Codable, Hashable, Sendable {
    public let placeID: UUID
    public let placeName: String
    public let placeType: PlaceType
    public let verified: Bool
    public let conditions: CheckinConditions
    public let note: String?
    public let catches: [ReportCatch]
    public let media: [ReportMedia]

    enum CodingKeys: String, CodingKey {
        case placeID = "place_id"
        case placeName = "place_name"
        case placeType = "place_type"
        case verified
        case conditions
        case note
        case catches
        case media
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        placeID = try c.decode(UUID.self, forKey: .placeID)
        placeName = try c.decode(String.self, forKey: .placeName)
        placeType = try c.decode(PlaceType.self, forKey: .placeType)
        verified = try c.decodeIfPresent(Bool.self, forKey: .verified) ?? false
        conditions = try c.decodeIfPresent(CheckinConditions.self, forKey: .conditions) ?? CheckinConditions()
        note = try c.decodeIfPresent(String.self, forKey: .note)
        catches = try c.decodeIfPresent([ReportCatch].self, forKey: .catches) ?? []
        media = try c.decodeIfPresent([ReportMedia].self, forKey: .media) ?? []
    }
}

/// Новое место друга в ленте.
public struct FeedPlace: Codable, Hashable, Sendable {
    public let placeType: PlaceType
    public let name: String
    public let isApproximate: Bool

    enum CodingKeys: String, CodingKey {
        case placeType = "place_type"
        case name
        case isApproximate = "approximate"
    }
}

/// Отзыв друга в ленте.
public struct FeedReview: Codable, Hashable, Sendable {
    public let placeID: UUID
    public let placeName: String
    public let placeType: PlaceType
    public let rating: Int
    public let body: String?

    enum CodingKeys: String, CodingKey {
        case placeID = "place_id"
        case placeName = "place_name"
        case placeType = "place_type"
        case rating
        case body
    }
}

/// С какой записи продолжать ленту: время и id последней показанной.
public struct FeedCursor: Hashable, Sendable {
    public let at: Date
    public let id: UUID

    public init(at: Date, id: UUID) {
        self.at = at
        self.id = id
    }
}

/// Запись ленты друзей — строка `friends_feed`.
public struct FeedItem: Codable, Identifiable, Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        case trip(FeedTrip)
        case checkin(FeedCheckin)
        case place(FeedPlace)
        case review(FeedReview)
        /// Вид записи из новой версии сервера (например, отзыв) — эта версия приложения его не показывает.
        case unsupported
    }

    public let id: UUID
    public let at: Date
    public let author: FeedAuthor
    public let content: Content

    public init(id: UUID, at: Date, author: FeedAuthor, content: Content) {
        self.id = id
        self.at = at
        self.author = author
        self.content = content
    }

    public var cursor: FeedCursor { FeedCursor(at: at, id: id) }

    /// Объект реакции («респект») для записи; у нового места реакций нет.
    public var reactionKey: ReactionKey? {
        switch content {
        case .trip: ReactionKey(.trip, id)
        case .checkin: ReactionKey(.checkin, id)
        case .review: ReactionKey(.review, id)
        case .place, .unsupported: nil
        }
    }

    public var isSupported: Bool {
        if case .unsupported = content { return false }
        return true
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case id
        case at
        case authorID = "author_id"
        case authorUsername = "author_username"
        case authorDisplayName = "author_display_name"
        case authorAvatarPath = "author_avatar_path"
        case data
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        at = try c.decode(Date.self, forKey: .at)
        author = FeedAuthor(
            id: try c.decode(UUID.self, forKey: .authorID),
            username: try c.decodeIfPresent(String.self, forKey: .authorUsername),
            displayName: try c.decodeIfPresent(String.self, forKey: .authorDisplayName),
            avatarPath: try c.decodeIfPresent(String.self, forKey: .authorAvatarPath)
        )
        // Незнакомый вид записи или поле — не ошибка всей страницы, а запись, которую не показываем.
        switch try c.decode(String.self, forKey: .kind) {
        case "trip":
            content = (try? c.decode(FeedTrip.self, forKey: .data)).map(Content.trip) ?? .unsupported
        case "checkin":
            content = (try? c.decode(FeedCheckin.self, forKey: .data)).map(Content.checkin) ?? .unsupported
        case "place":
            content = (try? c.decode(FeedPlace.self, forKey: .data)).map(Content.place) ?? .unsupported
        case "review":
            content = (try? c.decode(FeedReview.self, forKey: .data)).map(Content.review) ?? .unsupported
        default:
            content = .unsupported
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(at, forKey: .at)
        try c.encode(author.id, forKey: .authorID)
        try c.encodeIfPresent(author.username, forKey: .authorUsername)
        try c.encodeIfPresent(author.displayName, forKey: .authorDisplayName)
        try c.encodeIfPresent(author.avatarPath, forKey: .authorAvatarPath)
        switch content {
        case .trip(let trip):
            try c.encode("trip", forKey: .kind)
            try c.encode(trip, forKey: .data)
        case .checkin(let checkin):
            try c.encode("checkin", forKey: .kind)
            try c.encode(checkin, forKey: .data)
        case .place(let place):
            try c.encode("place", forKey: .kind)
            try c.encode(place, forKey: .data)
        case .review(let review):
            try c.encode("review", forKey: .kind)
            try c.encode(review, forKey: .data)
        case .unsupported:
            try c.encode("unsupported", forKey: .kind)
        }
    }
}

/// Страница ленты. `next` — курсор следующей страницы; `nil` — записей больше нет.
public struct FeedPage: Sendable {
    public let items: [FeedItem]
    public let next: FeedCursor?

    public init(items: [FeedItem], next: FeedCursor?) {
        self.items = items
        self.next = next
    }

    /// Страница из ответа сервера: неизвестные записи скрыты, но курсор — по последней полученной,
    /// иначе следующая страница начнётся с них снова.
    public init(rows: [FeedItem], limit: Int) {
        items = rows.filter(\.isSupported)
        next = rows.count >= limit ? rows.last?.cursor : nil
    }
}

// MARK: - Зоны приватности

/// Зона приватности (дом, дача): другие не видят трек поездок внутри неё. Строка `privacy_zones`.
public struct PrivacyZone: Codable, Identifiable, Hashable, Sendable {
    public static let radiusRange = 200...1000
    public static let radiusStep = 50
    public static let defaultRadius = 500
    public static let nameLimit = 50
    /// Больше зон база не принимает.
    public static let limit = 10

    public let id: UUID
    public let name: String
    public let center: GeoPoint
    public let radiusM: Int

    public init(id: UUID, name: String, center: GeoPoint, radiusM: Int) {
        self.id = id
        self.name = name
        self.center = center
        self.radiusM = radiusM
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case geom
        case radiusM = "radius_m"
    }

    /// Точка из PostgREST — GeoJSON `Point`.
    struct Point: Codable {
        var type = "Point"
        var coordinates: [Double]
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        radiusM = try c.decode(Int.self, forKey: .radiusM)
        let point = try c.decode(Point.self, forKey: .geom)
        guard point.coordinates.count >= 2 else {
            throw DecodingError.dataCorruptedError(forKey: .geom, in: c, debugDescription: "point without coordinates")
        }
        center = GeoPoint(latitude: point.coordinates[1], longitude: point.coordinates[0])
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(radiusM, forKey: .radiusM)
        try c.encode(Point(coordinates: [center.longitude, center.latitude]), forKey: .geom)
    }
}

/// Новая или изменённая зона приватности из редактора.
public struct PrivacyZoneDraft: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var center: GeoPoint
    public var radiusM: Int
    /// Зона уже сохранена — изменения уходят как обновление.
    public let isExisting: Bool

    public init(center: GeoPoint, name: String = "", radiusM: Int = PrivacyZone.defaultRadius) {
        id = UUID()
        self.name = name
        self.center = center
        self.radiusM = radiusM
        isExisting = false
    }

    public init(editing zone: PrivacyZone) {
        id = zone.id
        name = zone.name
        center = zone.center
        radiusM = zone.radiusM
        isExisting = true
    }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isValid: Bool {
        (1...PrivacyZone.nameLimit).contains(trimmedName.count) && PrivacyZone.radiusRange.contains(radiusM)
    }

    /// Точка для базы (EWKT).
    public var ewkt: String {
        "SRID=4326;POINT(\(center.longitude) \(center.latitude))"
    }
}
