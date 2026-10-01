import Foundation

/// Какие фото места показывать (`place_photos.p_kind`).
public enum PlacePhotoKind: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case all
    /// Фото уловов.
    case catches
    /// Фото самого места (без улова).
    case place

    public var id: String { rawValue }
    public var titleKey: String { "place.photos.kind.\(rawValue)" }
}

/// Фото посетителя в галерее места — строка `place_photos`.
public struct PlacePhoto: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let checkinID: UUID
    public let catchID: UUID?
    public let path: String
    public let thumbnailPath: String
    public let width: Int?
    public let height: Int?
    /// Когда сделан отчёт (чекин) с этим фото.
    public let at: Date
    public let author: FeedAuthor
    public let isOwn: Bool

    public var isCatch: Bool { catchID != nil }

    enum CodingKeys: String, CodingKey {
        case id
        case checkinID = "checkin_id"
        case catchID = "catch_id"
        case path
        case thumbnailPath = "thumb_path"
        case width
        case height
        case at
        case authorID = "author_id"
        case authorUsername = "author_username"
        case authorDisplayName = "author_display_name"
        case authorAvatarPath = "author_avatar_path"
        case isOwn = "is_own"
    }

    public init(
        id: UUID,
        checkinID: UUID,
        catchID: UUID? = nil,
        path: String,
        thumbnailPath: String,
        width: Int? = nil,
        height: Int? = nil,
        at: Date,
        author: FeedAuthor,
        isOwn: Bool = false
    ) {
        self.id = id
        self.checkinID = checkinID
        self.catchID = catchID
        self.path = path
        self.thumbnailPath = thumbnailPath
        self.width = width
        self.height = height
        self.at = at
        self.author = author
        self.isOwn = isOwn
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        checkinID = try c.decode(UUID.self, forKey: .checkinID)
        catchID = try c.decodeIfPresent(UUID.self, forKey: .catchID)
        path = try c.decode(String.self, forKey: .path)
        thumbnailPath = try c.decode(String.self, forKey: .thumbnailPath)
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        at = try c.decode(Date.self, forKey: .at)
        author = FeedAuthor(
            id: try c.decode(UUID.self, forKey: .authorID),
            username: try c.decodeIfPresent(String.self, forKey: .authorUsername),
            displayName: try c.decodeIfPresent(String.self, forKey: .authorDisplayName),
            avatarPath: try c.decodeIfPresent(String.self, forKey: .authorAvatarPath)
        )
        isOwn = try c.decodeIfPresent(Bool.self, forKey: .isOwn) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(checkinID, forKey: .checkinID)
        try c.encodeIfPresent(catchID, forKey: .catchID)
        try c.encode(path, forKey: .path)
        try c.encode(thumbnailPath, forKey: .thumbnailPath)
        try c.encodeIfPresent(width, forKey: .width)
        try c.encodeIfPresent(height, forKey: .height)
        try c.encode(at, forKey: .at)
        try c.encode(author.id, forKey: .authorID)
        try c.encodeIfPresent(author.username, forKey: .authorUsername)
        try c.encodeIfPresent(author.displayName, forKey: .authorDisplayName)
        try c.encodeIfPresent(author.avatarPath, forKey: .authorAvatarPath)
        try c.encode(isOwn, forKey: .isOwn)
    }

    /// Подпись автора: имя, иначе @username.
    public var authorName: String {
        if let name = author.displayName, !name.isEmpty { return name }
        return author.username.map { "@" + $0 } ?? ""
    }
}
