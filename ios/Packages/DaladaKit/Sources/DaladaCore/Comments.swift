import Foundation

// MARK: - Комментарии к постам

/// Комментарий к поездке, отчёту или отзыву — строка `post_comments`.
public struct PostComment: Decodable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let author: FeedAuthor
    public let body: String
    public let createdAt: Date
    public let editedAt: Date?
    /// Можно удалить: свой комментарий или комментарий под своим постом.
    public let canDelete: Bool

    public init(id: UUID, author: FeedAuthor, body: String, createdAt: Date, editedAt: Date? = nil, canDelete: Bool) {
        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.canDelete = canDelete
    }

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case authorUsername = "author_username"
        case authorDisplayName = "author_display_name"
        case authorAvatarPath = "author_avatar_path"
        case body
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case canDelete = "can_delete"
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
        canDelete = try c.decodeIfPresent(Bool.self, forKey: .canDelete) ?? false
    }
}

/// Новый комментарий. `id` создаётся на телефоне: повторная отправка не создаст дубль.
public struct CommentDraft: Equatable, Sendable {
    public static let maxLength = 1000

    public let id: UUID
    public let target: ReactionKey
    public var body: String

    public init(id: UUID = UUID(), target: ReactionKey, body: String = "") {
        self.id = id
        self.target = target
        self.body = body
    }

    public var trimmedBody: String { body.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isValid: Bool { !trimmedBody.isEmpty && trimmedBody.count <= Self.maxLength }

    /// Комментировать можно поездку, отчёт и отзыв (как в базе).
    public static func canComment(_ target: ReactionTarget) -> Bool {
        switch target {
        case .trip, .checkin, .review: true
        case .post: false
        }
    }
}

/// Строка `comment_summary`: сколько комментариев у поста.
public struct CommentSummaryRow: Decodable, Sendable {
    public let key: ReactionKey
    public let count: Int

    enum CodingKeys: String, CodingKey {
        case kind = "target_kind"
        case id = "target_id"
        case count = "comments_count"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = ReactionKey(try c.decode(ReactionTarget.self, forKey: .kind), try c.decode(UUID.self, forKey: .id))
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }
}

// MARK: - Ссылки из уведомлений

/// Поездка: `dalada://trip/<id>` (комментарий к поездке, поездка друга).
public enum TripLink {
    static let host = "trip"

    public static func url(tripID: UUID) -> URL {
        URL(string: "\(InviteLink.scheme)://\(host)/\(tripID.uuidString.lowercased())")!
    }

    public static func tripID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == InviteLink.scheme, url.host?.lowercased() == host else { return nil }
        return url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
    }
}

/// Комментарии к отчёту или отзыву: `dalada://comments/<checkin|review>/<id>`.
public enum CommentsLink {
    static let host = "comments"

    public static func url(_ key: ReactionKey) -> URL? {
        guard CommentDraft.canComment(key.kind) else { return nil }
        return URL(string: "\(InviteLink.scheme)://\(host)/\(key.kind.rawValue)/\(key.id.uuidString.lowercased())")
    }

    public static func key(from url: URL) -> ReactionKey? {
        guard url.scheme?.lowercased() == InviteLink.scheme, url.host?.lowercased() == host else { return nil }
        let parts = url.pathComponents.dropFirst()
        guard parts.count == 2,
              let kind = ReactionTarget(rawValue: parts[parts.startIndex].lowercased()),
              CommentDraft.canComment(kind),
              let id = UUID(uuidString: parts[parts.index(after: parts.startIndex)])
        else { return nil }
        return ReactionKey(kind, id)
    }
}
