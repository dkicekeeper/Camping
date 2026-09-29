import DaladaCore
import Foundation
import Supabase

/// Состояние соединения с бэкендом (для экрана профиля и диагностики в бете).
public enum ConnectionState: Sendable, Equatable {
    case notConfigured
    case checking
    case connected
    case failed(String)
}

/// Ошибки изменения профиля, которые экран показывает понятным текстом.
public enum ProfileUpdateError: Error, Sendable, Equatable {
    case usernameTaken
    case usernameInvalid
}

/// Единственная точка доступа к Supabase. Фичи работают с ним, а не с SDK напрямую.
public final class BackendClient: Sendable {
    /// Куда Supabase возвращает пользователя после входа через Google.
    /// Должен быть в Supabase → Authentication → URL Configuration → Redirect URLs.
    public static let oauthRedirectURL = URL(string: "dalada://auth-callback")!

    let supabase: SupabaseClient

    /// `nil`, если в конфигурации нет адреса или ключа Supabase.
    public init?(config: AppConfig) {
        guard let url = config.supabaseURL, let key = config.supabaseKey else { return nil }
        supabase = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: Self.oauthRedirectURL,
                    // Сохранённая сессия отдаётся сразу; если она истекла, SDK обновит её сам
                    // и пришлёт tokenRefreshed (или signedOut, если обновить не удалось).
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    /// Проверяет, что сервер отвечает и миграции применены: вызывает публичную RPC
    /// `places_in_bbox` на крошечной области (доступна и гостю).
    public func checkConnection() async -> ConnectionState {
        let probe = BoundingBoxParams(minLon: 76.88, minLat: 43.23, maxLon: 76.89, maxLat: 43.24, maxResults: 1)
        do {
            _ = try await supabase.rpc("places_in_bbox", params: probe).execute()
            return .connected
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

// MARK: - Вход

extension BackendClient {
    /// Есть ли сохранённая сессия.
    public var isSignedIn: Bool { supabase.auth.currentUser != nil }

    /// Изменения входа: id пользователя после входа, `nil` — гость. Первое значение приходит сразу.
    public func authChanges() -> AsyncStream<UUID?> {
        let auth = supabase.auth
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in auth.authStateChanges {
                    switch event {
                    case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                        continuation.yield(session?.user.id)
                    case .signedOut, .userDeleted:
                        continuation.yield(nil)
                    default:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Вход через Apple: identity token и исходный (не хешированный) nonce из запроса.
    /// Имя Apple отдаёт только при первом входе — сохраняем его в профиль.
    public func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws {
        try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
        if let fullName, !fullName.isEmpty {
            _ = try? await updateProfile(displayName: fullName)
        }
    }

    #if canImport(AuthenticationServices)
    /// Вход через Google: системное окно браузера (ASWebAuthenticationSession) и PKCE.
    public func signInWithGoogle() async throws {
        try await supabase.auth.signInWithOAuth(provider: .google, redirectTo: Self.oauthRedirectURL)
    }
    #endif

    public func signOut() async throws {
        try await supabase.auth.signOut()
    }
}

// MARK: - Профиль

extension BackendClient {
    /// Свой профиль. RLS отдаёт только свою строку.
    public func myProfile() async throws -> UserProfile {
        guard let userID = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        return try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .single()
            .execute()
            .value
    }

    /// Меняет поля своего профиля; `nil` — поле не трогаем.
    public func updateProfile(username: String? = nil, displayName: String? = nil) async throws -> UserProfile {
        guard let userID = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        let changes = ProfileChanges(username: username, displayName: displayName)
        do {
            return try await supabase
                .from("profiles")
                .update(changes)
                .eq("id", value: userID)
                .select()
                .single()
                .execute()
                .value
        } catch let error as PostgrestError {
            switch error.code {
            case "23505": throw ProfileUpdateError.usernameTaken
            case "22023", "23514": throw ProfileUpdateError.usernameInvalid
            default: throw error
            }
        }
    }

    /// Свободен ли username (формат, зарезервированные имена, занятость) — RPC `username_available`.
    public func isUsernameAvailable(_ username: String) async throws -> Bool {
        try await supabase
            .rpc("username_available", params: ["p_username": username])
            .execute()
            .value
    }
}

// MARK: - Параметры запросов

/// Поля для `update` профиля. `nil` не кодируется — такое поле не меняется.
struct ProfileChanges: Encodable, Sendable {
    let username: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case username
        case displayName = "display_name"
    }
}

/// Параметры RPC `places_in_bbox` (имена — как в SQL).
struct BoundingBoxParams: Encodable, Sendable {
    let minLon: Double
    let minLat: Double
    let maxLon: Double
    let maxLat: Double
    let maxResults: Int

    enum CodingKeys: String, CodingKey {
        case minLon = "min_lon"
        case minLat = "min_lat"
        case maxLon = "max_lon"
        case maxLat = "max_lat"
        case maxResults = "max_results"
    }
}
