import DaladaCore
import Foundation
import Supabase

// MARK: - Друзья

extension BackendClient {
    /// Поиск людей по @username (с начала) и имени (любая часть), от двух символов.
    public func searchProfiles(_ query: String, limit: Int = 20) async throws -> [PublicProfile] {
        try await supabase
            .rpc("search_profiles", params: SearchParams(query: query, limit: limit))
            .execute()
            .value
    }

    /// Профиль по username (ссылка-приглашение). `nil` — нет такого или заблокирован.
    public func profile(username: String) async throws -> PublicProfile? {
        let rows: [PublicProfile] = try await supabase
            .rpc("profile_by_username", params: ["p_username": username])
            .execute()
            .value
        return rows.first
    }

    public func myFriends() async throws -> [Friend] {
        try await supabase.rpc("my_friends").execute().value
    }

    public func myFriendRequests() async throws -> [FriendRequest] {
        try await supabase.rpc("my_friend_requests").execute().value
    }

    /// Отправить запрос. Если он уже прислал мне — сразу друзья.
    public func sendFriendRequest(to userID: UUID) async throws -> FriendRequestResult {
        try await supabase
            .rpc("send_friend_request", params: ["p_to": userID])
            .execute()
            .value
    }

    public func respondToFriendRequest(_ requestID: UUID, accept: Bool) async throws {
        try await supabase
            .rpc("respond_friend_request", params: RespondParams(request: requestID, accept: accept))
            .execute()
    }

    public func cancelFriendRequest(_ requestID: UUID) async throws {
        try await supabase.rpc("cancel_friend_request", params: ["p_request": requestID]).execute()
    }

    public func removeFriend(_ userID: UUID) async throws {
        try await supabase.rpc("remove_friend", params: ["p_friend": userID]).execute()
    }

    /// Блокировка разрывает дружбу и прячет нас друг от друга (поиск, места, отчёты).
    public func block(_ userID: UUID) async throws {
        do {
            try await supabase.from("blocks").insert(["blocked_id": userID], returning: .minimal).execute()
        } catch let error as PostgrestError where error.code == "23505" {
            return
        }
    }

    public func unblock(_ userID: UUID) async throws {
        try await supabase.from("blocks").delete().eq("blocked_id", value: userID).execute()
    }

    public func myBlocks() async throws -> [BlockedUser] {
        try await supabase.rpc("my_blocks").execute().value
    }
}

struct SearchParams: Encodable, Sendable {
    let query: String
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case query = "p_query"
        case limit = "p_limit"
    }
}

struct RespondParams: Encodable, Sendable {
    let request: UUID
    let accept: Bool

    enum CodingKeys: String, CodingKey {
        case request = "p_request"
        case accept = "p_accept"
    }
}
