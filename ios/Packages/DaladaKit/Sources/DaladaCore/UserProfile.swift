import Foundation

/// Свой профиль (строка `public.profiles`).
public struct UserProfile: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var username: String?
    public var displayName: String?
    public var avatarPath: String?
    public var city: String?
    public var language: String
    /// Какую версию условий и политики человек принял (`LegalDocuments.version`); `nil` — никакую.
    public var termsVersion: Int?
    /// Уведомления о новых поездках и отчётах друзей; `nil` — старый ответ без поля (включены).
    public var notifyFriendPosts: Bool?
    /// Остальные виды уведомлений и «тихие часы» (`nil` — старый ответ без полей).
    public var notifyReplies: Bool?
    public var notifyFriendRequests: Bool?
    public var notifyComments: Bool?
    public var notifyBans: Bool?
    public var notifyPlaceActivity: Bool?
    public var quietFrom: Int?
    public var quietTo: Int?

    public init(
        id: UUID,
        username: String? = nil,
        displayName: String? = nil,
        avatarPath: String? = nil,
        city: String? = nil,
        language: String = "ru",
        termsVersion: Int? = nil,
        notifyFriendPosts: Bool? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.city = city
        self.language = language
        self.termsVersion = termsVersion
        self.notifyFriendPosts = notifyFriendPosts
    }

    /// Нужно принять условия и политику (новый человек или документы изменились).
    public var needsTermsConsent: Bool {
        (termsVersion ?? 0) < LegalDocuments.version
    }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case city
        case language
        case termsVersion = "terms_version"
        case notifyFriendPosts = "notify_friend_posts"
        case notifyReplies = "notify_replies"
        case notifyFriendRequests = "notify_friend_requests"
        case notifyComments = "notify_comments"
        case notifyBans = "notify_bans"
        case notifyPlaceActivity = "notify_place_activity"
        case quietFrom = "quiet_from"
        case quietTo = "quiet_to"
    }

    /// Настройки уведомлений из профиля (чего нет в ответе — включено).
    public var notificationSettings: NotificationSettings {
        NotificationSettings(
            replies: notifyReplies ?? true,
            friendRequests: notifyFriendRequests ?? true,
            comments: notifyComments ?? true,
            friendPosts: notifyFriendPosts ?? true,
            bans: notifyBans ?? true,
            placeActivity: notifyPlaceActivity ?? true,
            quietHours: quietFrom.flatMap { from in quietTo.map { QuietHours(from: from, to: $0) } }
        )
    }
}

/// Правила username — те же, что в базе (`private.username_is_valid`), кроме списка
/// зарезервированных имён: его проверяет только сервер (`username_available`).
public enum UsernameRules {
    public static let lengthRange = 3...30

    private static let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.")

    /// Как база сохранит введённое значение: без пробелов по краям, в нижнем регистре.
    public static func normalized(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Подходит ли формат (после нормализации).
    public static func isValidFormat(_ input: String) -> Bool {
        let username = normalized(input)
        guard lengthRange.contains(username.count),
              username.allSatisfy({ allowed.contains($0) })
        else { return false }
        return !username.hasPrefix(".") && !username.hasSuffix(".") && !username.contains("..")
    }
}

/// Криптостойкая случайная строка (например, nonce для Sign in with Apple).
public enum SecureRandom {
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    public static func string(length: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }
}

// MARK: - Настройки уведомлений

/// Какие уведомления присылать и «тихие часы» (колонки `profiles`).
public struct NotificationSettings: Equatable, Sendable {
    public var replies: Bool
    public var friendRequests: Bool
    public var comments: Bool
    public var friendPosts: Bool
    public var bans: Bool
    public var placeActivity: Bool
    /// `nil` — без тихих часов.
    public var quietHours: QuietHours?

    public init(
        replies: Bool = true,
        friendRequests: Bool = true,
        comments: Bool = true,
        friendPosts: Bool = true,
        bans: Bool = true,
        placeActivity: Bool = true,
        quietHours: QuietHours? = nil
    ) {
        self.replies = replies
        self.friendRequests = friendRequests
        self.comments = comments
        self.friendPosts = friendPosts
        self.bans = bans
        self.placeActivity = placeActivity
        self.quietHours = quietHours
    }
}

/// «Тихие часы» по времени Алматы: с `from` до `to` (часы 0–23, может переходить через полночь).
/// Уведомления в это время приходят, когда тихие часы закончатся.
public struct QuietHours: Equatable, Sendable {
    public static let `default` = QuietHours(from: 22, to: 8)

    public var from: Int
    public var to: Int

    public init(from: Int, to: Int) {
        self.from = min(max(from, 0), 23)
        self.to = min(max(to, 0), 23)
    }

    /// Час `hour` (0–23) внутри тихих часов; одинаковые начало и конец — тихих часов нет.
    public func contains(hour: Int) -> Bool {
        if from == to { return false }
        return from < to ? (hour >= from && hour < to) : (hour >= from || hour < to)
    }
}

extension NotificationSettings: Encodable {
    enum CodingKeys: String, CodingKey {
        case replies = "notify_replies"
        case friendRequests = "notify_friend_requests"
        case comments = "notify_comments"
        case friendPosts = "notify_friend_posts"
        case bans = "notify_bans"
        case placeActivity = "notify_place_activity"
        case quietFrom = "quiet_from"
        case quietTo = "quiet_to"
    }

    /// Для `update` профиля: без тихих часов — `null` в обеих колонках.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(replies, forKey: .replies)
        try c.encode(friendRequests, forKey: .friendRequests)
        try c.encode(comments, forKey: .comments)
        try c.encode(friendPosts, forKey: .friendPosts)
        try c.encode(bans, forKey: .bans)
        try c.encode(placeActivity, forKey: .placeActivity)
        try c.encode(quietHours?.from, forKey: .quietFrom)
        try c.encode(quietHours?.to, forKey: .quietTo)
    }
}
