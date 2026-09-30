import Foundation

// MARK: - Календарный день

/// День без времени и часового пояса — колонка `date` в базе («2026-09-27»).
public struct CalendarDay: Codable, Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// День, на который приходится `date` в календаре `calendar` (по умолчанию — на телефоне).
    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 1970
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    /// «2026-09-27»; `nil` — строка не в этом виде.
    public init?(string: String) {
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        year = parts[0]
        month = parts[1]
        day = parts[2]
    }

    public var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Полдень этого дня в календаре `calendar` — для показа и выбора даты.
    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        guard let day = CalendarDay(string: raw) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a date: \(raw)")
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }
}

// MARK: - Реакции

/// На что ставится реакция («респект», «полезно»).
public enum ReactionTarget: String, Codable, Sendable {
    case trip
    case checkin
    case review
    case post
}

/// Объект реакции.
public struct ReactionKey: Hashable, Sendable {
    public let kind: ReactionTarget
    public let id: UUID

    public init(_ kind: ReactionTarget, _ id: UUID) {
        self.kind = kind
        self.id = id
    }
}

/// Сколько реакций и стоит ли моя.
public struct ReactionState: Hashable, Sendable {
    public var count: Int
    public var reacted: Bool

    public init(count: Int = 0, reacted: Bool = false) {
        self.count = count
        self.reacted = reacted
    }

    /// После нажатия: ставим или снимаем свою.
    public func toggled() -> ReactionState {
        ReactionState(count: max(count + (reacted ? -1 : 1), 0), reacted: !reacted)
    }
}

/// Строка `reaction_summary`.
public struct ReactionSummaryRow: Decodable, Sendable {
    public let key: ReactionKey
    public let state: ReactionState

    enum CodingKeys: String, CodingKey {
        case kind = "target_kind"
        case id = "target_id"
        case count = "reactions_count"
        case reacted
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = ReactionKey(try c.decode(ReactionTarget.self, forKey: .kind), try c.decode(UUID.self, forKey: .id))
        state = ReactionState(
            count: try c.decodeIfPresent(Int.self, forKey: .count) ?? 0,
            reacted: try c.decodeIfPresent(Bool.self, forKey: .reacted) ?? false
        )
    }
}

// MARK: - Отзывы

/// Порядок отзывов (`place_reviews`, параметр `p_order`).
public enum ReviewSort: String, CaseIterable, Identifiable, Sendable {
    case new
    case helpful
    case high
    case low

    public var id: String { rawValue }
    public var titleKey: String { "review.sort.\(rawValue)" }
}

/// Отзыв о месте — строка `place_reviews`.
public struct PlaceReview: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let author: FeedAuthor
    public let rating: Int
    public let body: String?
    public let visitedOn: CalendarDay?
    public let createdAt: Date
    public let editedAt: Date?
    public let isOwn: Bool
    public let helpful: ReactionState

    enum CodingKeys: String, CodingKey {
        case id = "review_id"
        case authorID = "author_id"
        case authorUsername = "author_username"
        case authorDisplayName = "author_display_name"
        case authorAvatarPath = "author_avatar_path"
        case rating
        case body
        case visitedOn = "visited_on"
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case isOwn = "is_own"
        case helpfulCount = "helpful_count"
        case markedHelpful = "marked_helpful"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        author = FeedAuthor(
            id: try c.decode(UUID.self, forKey: .authorID),
            username: try c.decodeIfPresent(String.self, forKey: .authorUsername),
            displayName: try c.decodeIfPresent(String.self, forKey: .authorDisplayName),
            avatarPath: try c.decodeIfPresent(String.self, forKey: .authorAvatarPath)
        )
        rating = try c.decode(Int.self, forKey: .rating)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        visitedOn = try c.decodeIfPresent(CalendarDay.self, forKey: .visitedOn)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)
        isOwn = try c.decodeIfPresent(Bool.self, forKey: .isOwn) ?? false
        helpful = ReactionState(
            count: try c.decodeIfPresent(Int.self, forKey: .helpfulCount) ?? 0,
            reacted: try c.decodeIfPresent(Bool.self, forKey: .markedHelpful) ?? false
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(author.id, forKey: .authorID)
        try c.encodeIfPresent(author.username, forKey: .authorUsername)
        try c.encodeIfPresent(author.displayName, forKey: .authorDisplayName)
        try c.encodeIfPresent(author.avatarPath, forKey: .authorAvatarPath)
        try c.encode(rating, forKey: .rating)
        try c.encodeIfPresent(body, forKey: .body)
        try c.encodeIfPresent(visitedOn, forKey: .visitedOn)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(editedAt, forKey: .editedAt)
        try c.encode(isOwn, forKey: .isOwn)
        try c.encode(helpful.count, forKey: .helpfulCount)
        try c.encode(helpful.reacted, forKey: .markedHelpful)
    }
}

/// Свой отзыв о месте (из сводки).
public struct MyReview: Hashable, Sendable {
    public let id: UUID
    public let rating: Int
    public let body: String?
    public let visitedOn: CalendarDay?
}

/// Сводка отзывов места — строка `place_review_summary`.
public struct ReviewSummary: Decodable, Hashable, Sendable {
    public let reviewsCount: Int
    public let ratingAverage: Double?
    /// Число отзывов с 1, 2, 3, 4 и 5 звёздами.
    public let stars: [Int]
    /// Есть чекин в месте — можно оставить отзыв.
    public let canReview: Bool
    public let myReview: MyReview?

    enum CodingKeys: String, CodingKey {
        case reviewsCount = "reviews_count"
        case ratingAverage = "rating_avg"
        case stars
        case canReview = "can_review"
        case myReviewID = "my_review_id"
        case myRating = "my_rating"
        case myBody = "my_body"
        case myVisitedOn = "my_visited_on"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reviewsCount = try c.decodeIfPresent(Int.self, forKey: .reviewsCount) ?? 0
        ratingAverage = try c.decodeIfPresent(Double.self, forKey: .ratingAverage)
        let decodedStars = try c.decodeIfPresent([Int].self, forKey: .stars) ?? []
        stars = decodedStars.count == 5 ? decodedStars : Array(repeating: 0, count: 5)
        canReview = try c.decodeIfPresent(Bool.self, forKey: .canReview) ?? false
        if let id = try c.decodeIfPresent(UUID.self, forKey: .myReviewID),
           let rating = try c.decodeIfPresent(Int.self, forKey: .myRating) {
            myReview = MyReview(
                id: id,
                rating: rating,
                body: try c.decodeIfPresent(String.self, forKey: .myBody),
                visitedOn: try c.decodeIfPresent(CalendarDay.self, forKey: .myVisitedOn)
            )
        } else {
            myReview = nil
        }
    }

    /// Доля отзывов с `star` звёздами (0…1) — для полосок распределения.
    public func share(of star: Int) -> Double {
        guard reviewsCount > 0, (1...5).contains(star) else { return 0 }
        return Double(stars[star - 1]) / Double(reviewsCount)
    }
}

/// Отзыв из формы.
public struct ReviewDraft: Equatable, Sendable {
    public static let bodyLimit = 2000

    public let placeID: UUID
    /// 0 — оценка ещё не выбрана.
    public var rating: Int
    public var body: String
    public var visitedOn: CalendarDay

    public init(placeID: UUID, existing: MyReview? = nil, today: CalendarDay = CalendarDay(Date())) {
        self.placeID = placeID
        rating = existing?.rating ?? 0
        body = existing?.body ?? ""
        visitedOn = existing?.visitedOn ?? today
    }

    public var trimmedBody: String { body.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isValid: Bool {
        (1...5).contains(rating) && trimmedBody.count <= Self.bodyLimit
    }
}

// MARK: - Обсуждения

/// Обсуждение в списке места — строка `place_threads`.
public struct ThreadSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let author: FeedAuthor
    public let title: String
    public let bodyPreview: String
    public let postsCount: Int
    public let lastActivityAt: Date
    public let createdAt: Date
    public let isOwn: Bool

    enum CodingKeys: String, CodingKey {
        case id = "thread_id"
        case authorID = "author_id"
        case authorUsername = "author_username"
        case authorDisplayName = "author_display_name"
        case authorAvatarPath = "author_avatar_path"
        case title
        case bodyPreview = "body_preview"
        case postsCount = "posts_count"
        case lastActivityAt = "last_activity_at"
        case createdAt = "created_at"
        case isOwn = "is_own"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        author = FeedAuthor(
            id: try c.decode(UUID.self, forKey: .authorID),
            username: try c.decodeIfPresent(String.self, forKey: .authorUsername),
            displayName: try c.decodeIfPresent(String.self, forKey: .authorDisplayName),
            avatarPath: try c.decodeIfPresent(String.self, forKey: .authorAvatarPath)
        )
        title = try c.decode(String.self, forKey: .title)
        bodyPreview = try c.decodeIfPresent(String.self, forKey: .bodyPreview) ?? ""
        postsCount = try c.decodeIfPresent(Int.self, forKey: .postsCount) ?? 0
        lastActivityAt = try c.decode(Date.self, forKey: .lastActivityAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        isOwn = try c.decodeIfPresent(Bool.self, forKey: .isOwn) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(author.id, forKey: .authorID)
        try c.encodeIfPresent(author.username, forKey: .authorUsername)
        try c.encodeIfPresent(author.displayName, forKey: .authorDisplayName)
        try c.encodeIfPresent(author.avatarPath, forKey: .authorAvatarPath)
        try c.encode(title, forKey: .title)
        try c.encode(bodyPreview, forKey: .bodyPreview)
        try c.encode(postsCount, forKey: .postsCount)
        try c.encode(lastActivityAt, forKey: .lastActivityAt)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(isOwn, forKey: .isOwn)
    }
}

/// Обсуждение целиком — строка `thread_view`.
public struct ThreadDetails: Decodable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let placeID: UUID
    public let placeName: String
    public let author: FeedAuthor
    public let title: String
    public let body: String
    public let postsCount: Int
    public let createdAt: Date
    public let editedAt: Date?
    public let isOwn: Bool

    enum CodingKeys: String, CodingKey {
        case id = "thread_id"
        case placeID = "place_id"
        case placeName = "place_name"
        case authorID = "author_id"
        case authorUsername = "author_username"
        case authorDisplayName = "author_display_name"
        case authorAvatarPath = "author_avatar_path"
        case title
        case body
        case postsCount = "posts_count"
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case isOwn = "is_own"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        placeID = try c.decode(UUID.self, forKey: .placeID)
        placeName = try c.decode(String.self, forKey: .placeName)
        author = FeedAuthor(
            id: try c.decode(UUID.self, forKey: .authorID),
            username: try c.decodeIfPresent(String.self, forKey: .authorUsername),
            displayName: try c.decodeIfPresent(String.self, forKey: .authorDisplayName),
            avatarPath: try c.decodeIfPresent(String.self, forKey: .authorAvatarPath)
        )
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        postsCount = try c.decodeIfPresent(Int.self, forKey: .postsCount) ?? 0
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)
        isOwn = try c.decodeIfPresent(Bool.self, forKey: .isOwn) ?? false
    }
}

/// Цитата в ответе: автор и начало цитируемого ответа.
public struct PostQuote: Codable, Hashable, Sendable {
    public let postID: UUID
    public let authorUsername: String?
    public let authorDisplayName: String?
    public let body: String

    public init(postID: UUID, authorUsername: String?, authorDisplayName: String?, body: String) {
        self.postID = postID
        self.authorUsername = authorUsername
        self.authorDisplayName = authorDisplayName
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case authorUsername = "author_username"
        case authorDisplayName = "author_display_name"
        case body
    }
}

/// Ответ в обсуждении — строка `thread_posts`.
public struct ThreadPost: Decodable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let author: FeedAuthor
    public let body: String
    public let createdAt: Date
    public let editedAt: Date?
    public let isOwn: Bool
    public let quote: PostQuote?
    public let reactions: ReactionState

    enum CodingKeys: String, CodingKey {
        case id = "post_id"
        case authorID = "author_id"
        case authorUsername = "author_username"
        case authorDisplayName = "author_display_name"
        case authorAvatarPath = "author_avatar_path"
        case body
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case isOwn = "is_own"
        case quote
        case reactionsCount = "reactions_count"
        case reacted
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        author = FeedAuthor(
            id: try c.decode(UUID.self, forKey: .authorID),
            username: try c.decodeIfPresent(String.self, forKey: .authorUsername),
            displayName: try c.decodeIfPresent(String.self, forKey: .authorDisplayName),
            avatarPath: try c.decodeIfPresent(String.self, forKey: .authorAvatarPath)
        )
        body = try c.decode(String.self, forKey: .body)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)
        isOwn = try c.decodeIfPresent(Bool.self, forKey: .isOwn) ?? false
        quote = try? c.decodeIfPresent(PostQuote.self, forKey: .quote)
        reactions = ReactionState(
            count: try c.decodeIfPresent(Int.self, forKey: .reactionsCount) ?? 0,
            reacted: try c.decodeIfPresent(Bool.self, forKey: .reacted) ?? false
        )
    }
}

/// Новое обсуждение из формы.
public struct ThreadDraft: Equatable, Sendable {
    public static let titleRange = 3...120
    public static let bodyLimit = 4000

    public let id: UUID
    public let placeID: UUID
    public var title: String
    public var body: String

    public init(placeID: UUID, id: UUID = UUID()) {
        self.id = id
        self.placeID = placeID
        title = ""
        body = ""
    }

    public var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trimmedBody: String { body.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isValid: Bool {
        Self.titleRange.contains(trimmedTitle.count) && (1...Self.bodyLimit).contains(trimmedBody.count)
    }
}

/// Ответ из поля ввода.
public struct PostDraft: Equatable, Sendable {
    public static let bodyLimit = 4000

    public let id: UUID
    public let threadID: UUID
    public var body: String
    public var quote: PostQuote?

    public init(threadID: UUID, id: UUID = UUID()) {
        self.id = id
        self.threadID = threadID
        body = ""
        quote = nil
    }

    public var trimmedBody: String { body.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isValid: Bool { (1...Self.bodyLimit).contains(trimmedBody.count) }
}

// MARK: - Ошибки

/// Отказы базы для отзывов, обсуждений и жалоб (коды DL001–DL003, DL005).
public enum CommunityRefusal: String, Sendable {
    /// Отзыв — только после чекина в месте.
    case checkinRequired = "DL001"
    /// Отзывы и обсуждения — только в публичных местах.
    case publicPlacesOnly = "DL002"
    /// Слишком часто.
    case tooOften = "DL003"
    /// В тексте грубые слова.
    case badWords = "DL005"

    public var messageKey: String {
        switch self {
        case .checkinRequired: "community.error.checkinRequired"
        case .publicPlacesOnly: "community.error.publicOnly"
        case .tooOften: "community.error.tooOften"
        case .badWords: "moderation.error.badWords"
        }
    }
}
