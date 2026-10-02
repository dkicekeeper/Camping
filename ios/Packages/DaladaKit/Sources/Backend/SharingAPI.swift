import DaladaCore
import Foundation
import Supabase

// MARK: - Профиль другого человека и лента «Главной»

extension BackendClient {
    /// Поездки человека, которые я вижу (RPC `user_trips`), новые сверху. `before` — `startedAt`
    /// последней показанной для следующей страницы.
    public func userTrips(_ userID: UUID, limit: Int = 20, before: Date? = nil) async throws -> [TripSummary] {
        try await supabase
            .rpc("user_trips", params: UserTripsParams(user: userID, limit: limit, before: before))
            .execute()
            .value
    }

    /// Места человека, которые я вижу (RPC `user_places`); приблизительные — смещённым кругом.
    public func userPlaces(_ userID: UUID) async throws -> [PlaceSummary] {
        try await supabase
            .rpc("user_places", params: ["p_user": userID])
            .execute()
            .value
    }

    /// Итоги человека по тому, что я вижу (RPC `user_stats`). `nil` — заблокирован или не найден.
    public func userStats(_ userID: UUID) async throws -> UserPublicStats? {
        let rows: [UserPublicStats] = try await supabase
            .rpc("user_stats", params: ["p_user": userID])
            .execute()
            .value
        return rows.first
    }

    /// Страница ленты «Главной» (RPC `home_feed`): записи друзей и свои, обсуждения публичных
    /// мест; гостю — только обсуждения. `after` — курсор предыдущей страницы.
    public func homeFeed(limit: Int = 20, after cursor: FeedCursor? = nil) async throws -> FeedPage {
        let rows: [FeedItem] = try await supabase
            .rpc("home_feed", params: FeedParams(limit: limit, cursor: cursor))
            .execute()
            .value
        return FeedPage(rows: rows, limit: limit)
    }
}

struct UserTripsParams: Encodable, Sendable {
    let user: UUID
    let limit: Int
    let before: Date?

    enum CodingKeys: String, CodingKey {
        case user = "p_user"
        case limit = "p_limit"
        case before = "p_before"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(user, forKey: .user)
        try c.encode(limit, forKey: .limit)
        try c.encode(before.map(PostgresTimestamp.string), forKey: .before)
    }
}

struct FeedParams: Encodable, Sendable {
    let limit: Int
    let cursor: FeedCursor?

    enum CodingKeys: String, CodingKey {
        case limit = "p_limit"
        case beforeAt = "p_before_at"
        case beforeID = "p_before_id"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(limit, forKey: .limit)
        try c.encode(cursor.map { PostgresTimestamp.string($0.at) }, forKey: .beforeAt)
        try c.encode(cursor?.id, forKey: .beforeID)
    }
}

// MARK: - Зоны приватности

extension BackendClient {
    public func privacyZones() async throws -> [PrivacyZone] {
        try await supabase
            .from("privacy_zones")
            .select("id,name,geom,radius_m")
            .order("created_at")
            .execute()
            .value
    }

    /// Новая зона — вставка (id задаёт телефон), существующая — обновление.
    public func savePrivacyZone(_ draft: PrivacyZoneDraft) async throws {
        let row = PrivacyZoneRow(draft)
        if draft.isExisting {
            try await supabase
                .from("privacy_zones")
                .update(row.changes)
                .eq("id", value: draft.id)
                .execute()
        } else {
            do {
                try await supabase.from("privacy_zones").insert(row, returning: .minimal).execute()
            } catch let error as PostgrestError where error.code == "23505" {
                return
            }
        }
    }

    public func deletePrivacyZone(_ id: UUID) async throws {
        try await supabase.from("privacy_zones").delete().eq("id", value: id).execute()
    }
}

struct PrivacyZoneRow: Encodable, Sendable {
    let id: UUID
    let name: String
    let geom: String
    let radiusM: Int

    init(_ draft: PrivacyZoneDraft) {
        id = draft.id
        name = draft.trimmedName
        geom = draft.ewkt
        radiusM = draft.radiusM
    }

    /// Изменяемые колонки (без id).
    var changes: Changes { Changes(name: name, geom: geom, radiusM: radiusM) }

    struct Changes: Encodable, Sendable {
        let name: String
        let geom: String
        let radiusM: Int

        enum CodingKeys: String, CodingKey {
            case name
            case geom
            case radiusM = "radius_m"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case geom
        case radiusM = "radius_m"
    }
}
