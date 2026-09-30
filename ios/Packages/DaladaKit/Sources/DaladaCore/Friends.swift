import Foundation

/// Состояние запроса в друзья между мной и другим человеком.
public enum FriendRequestDirection: String, Codable, Sendable {
    /// Он прислал мне — можно принять.
    case incoming
    /// Я отправил — ждём ответа, можно отменить.
    case outgoing
}

/// Человек в поиске или на странице профиля (`search_profiles`, `profile_by_username`).
public struct PublicProfile: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let username: String?
    public let displayName: String?
    public let avatarPath: String?
    public let city: String?
    public let isFriend: Bool
    public let requestStatus: FriendRequestDirection?

    public init(
        id: UUID,
        username: String?,
        displayName: String?,
        avatarPath: String? = nil,
        city: String? = nil,
        isFriend: Bool,
        requestStatus: FriendRequestDirection?
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.city = city
        self.isFriend = isFriend
        self.requestStatus = requestStatus
    }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case city
        case isFriend = "is_friend"
        case requestStatus = "request_status"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatarPath = try c.decodeIfPresent(String.self, forKey: .avatarPath)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        isFriend = try c.decodeIfPresent(Bool.self, forKey: .isFriend) ?? false
        requestStatus = try? c.decodeIfPresent(FriendRequestDirection.self, forKey: .requestStatus)
    }

    /// Та же страница после действия («Запрос отправлен», «Друзья»).
    public func with(isFriend: Bool, requestStatus: FriendRequestDirection?) -> PublicProfile {
        PublicProfile(
            id: id,
            username: username,
            displayName: displayName,
            avatarPath: avatarPath,
            city: city,
            isFriend: isFriend,
            requestStatus: requestStatus
        )
    }
}

/// Друг — строка `my_friends`.
public struct Friend: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let username: String?
    public let displayName: String?
    public let avatarPath: String?
    public let city: String?
    public let since: Date

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case city
        case since
    }
}

/// Ожидающий запрос — строка `my_friend_requests`.
public struct FriendRequest: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let direction: FriendRequestDirection
    public let userID: UUID
    public let username: String?
    public let displayName: String?
    public let avatarPath: String?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "request_id"
        case direction
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case createdAt = "created_at"
    }
}

/// Заблокированный — строка `my_blocks`.
public struct BlockedUser: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let username: String?
    public let displayName: String?
    public let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case username
        case displayName = "display_name"
        case avatarPath = "avatar_path"
    }
}

/// Ответ `send_friend_request`.
public enum FriendRequestResult: String, Codable, Sendable {
    case sent
    /// Он уже прислал мне запрос — сразу друзья.
    case accepted
    case alreadyFriends = "already_friends"
}

/// Ссылка-приглашение в профиль: `dalada://u/<username>` (QR-код, «Поделиться»).
/// Когда появится домен — добавим `https://dalada.app/u/<username>`.
public enum InviteLink {
    public static let scheme = "dalada"
    static let profileHost = "u"

    public static func url(username: String) -> URL? {
        guard UsernameRules.isValidFormat(username) else { return nil }
        return URL(string: "\(scheme)://\(profileHost)/\(username)")
    }

    /// Username из ссылки приглашения; `nil` — это не приглашение (например, возврат из входа).
    public static func username(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == profileHost else { return nil }
        let username = url.pathComponents.dropFirst().first?.lowercased() ?? ""
        return UsernameRules.isValidFormat(username) ? username : nil
    }
}
