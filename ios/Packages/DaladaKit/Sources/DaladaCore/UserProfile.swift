import Foundation

/// Свой профиль (строка `public.profiles`).
public struct UserProfile: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var username: String?
    public var displayName: String?
    public var avatarPath: String?
    public var city: String?
    public var language: String

    public init(
        id: UUID,
        username: String? = nil,
        displayName: String? = nil,
        avatarPath: String? = nil,
        city: String? = nil,
        language: String = "ru"
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.city = city
        self.language = language
    }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case city
        case language
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
