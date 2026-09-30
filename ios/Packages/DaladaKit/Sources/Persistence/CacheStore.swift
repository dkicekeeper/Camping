import Foundation
import GRDB

/// Кэш последних ответов сервера: показываем их, пока нет сети.
/// Данные пользователя лежат под его префиксом и стираются при выходе из аккаунта.
public struct CacheStore: Sendable {
    let writer: any DatabaseWriter

    public func save<T: Encodable & Sendable>(_ value: T, for key: CacheKey, now: Date = Date()) async throws {
        let data = try JSONEncoder().encode(value)
        try await writer.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO cache_entry (key, value, updated_at) VALUES (?, ?, ?)",
                arguments: [key.rawValue, data, now]
            )
        }
    }

    public func load<T: Decodable & Sendable>(_ type: T.Type, for key: CacheKey) async throws -> T? {
        let data = try await writer.read { db in
            try Data.fetchOne(db, sql: "SELECT value FROM cache_entry WHERE key = ?", arguments: [key.rawValue])
        }
        guard let data else { return nil }
        // Формат мог устареть после обновления приложения — тогда просто нет кэша.
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Стирает всё, что закэшировано для пользователя (при выходе из аккаунта).
    public func removeUserData(_ userID: UUID) async throws {
        let prefix = CacheKey.userPrefix(userID)
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM cache_entry WHERE substr(key, 1, length(?)) = ?",
                arguments: [prefix, prefix]
            )
        }
    }
}

/// Ключ кэша. Всё, что зависит от зрителя, — под префиксом `user/<id>/` или `guest/`.
public struct CacheKey: Hashable, Sendable {
    public let rawValue: String

    /// Справочник рыб — общий для всех.
    public static let species = CacheKey(rawValue: "shared/species")

    /// Правила и запреты (зоны с границами) — общие для всех, нужны без сети.
    public static let rules = CacheKey(rawValue: "shared/rules")

    /// Шаблоны чеклистов редакции — общие для всех, нужны без сети.
    public static let checklistTemplates = CacheKey(rawValue: "shared/checklist_templates")

    public static func profile(_ user: UUID) -> CacheKey {
        CacheKey(rawValue: userPrefix(user) + "profile")
    }

    public static func myPlaces(_ user: UUID) -> CacheKey {
        CacheKey(rawValue: userPrefix(user) + "my_places")
    }

    public static func myCatches(_ user: UUID) -> CacheKey {
        CacheKey(rawValue: userPrefix(user) + "my_catches")
    }

    public static func stats(_ user: UUID) -> CacheKey {
        CacheKey(rawValue: userPrefix(user) + "stats")
    }

    public static func myTrips(_ user: UUID) -> CacheKey {
        CacheKey(rawValue: userPrefix(user) + "my_trips")
    }

    /// Первая страница ленты друзей.
    public static func feed(_ user: UUID) -> CacheKey {
        CacheKey(rawValue: userPrefix(user) + "feed")
    }

    public static func trip(_ id: UUID, viewer: UUID?) -> CacheKey {
        CacheKey(rawValue: viewerPrefix(viewer) + "trip/" + id.uuidString.lowercased())
    }

    /// Последние места на карте.
    public static func mapPlaces(viewer: UUID?) -> CacheKey {
        CacheKey(rawValue: viewerPrefix(viewer) + "map_places")
    }

    public static func place(_ id: UUID, viewer: UUID?) -> CacheKey {
        CacheKey(rawValue: viewerPrefix(viewer) + "place/" + id.uuidString.lowercased())
    }

    public static func reports(_ place: UUID, viewer: UUID?) -> CacheKey {
        CacheKey(rawValue: viewerPrefix(viewer) + "reports/" + place.uuidString.lowercased())
    }

    static func userPrefix(_ user: UUID) -> String {
        "user/" + user.uuidString.lowercased() + "/"
    }

    static func viewerPrefix(_ viewer: UUID?) -> String {
        viewer.map(userPrefix) ?? "guest/"
    }
}
