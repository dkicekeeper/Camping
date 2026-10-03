import DaladaCore
import Foundation
import Supabase

// MARK: - Фото профиля и настройки уведомлений

extension BackendClient {
    /// Ставит фото профиля: загружает JPEG в свою папку бакета `media`, записывает путь в профиль и
    /// удаляет прежний файл. Возвращает обновлённый профиль.
    public func setAvatar(jpeg: Data) async throws -> UserProfile {
        guard let userID = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        let previous = try? await myProfile().avatarPath
        let path = MediaPath.full(owner: userID, media: UUID())
        try await supabase.storage
            .from(MediaPath.bucket)
            .upload(path, data: jpeg, options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg"))
        let profile = try await updateAvatarPath(path, userID: userID)
        if let previous, previous != path {
            _ = try? await supabase.storage.from(MediaPath.bucket).remove(paths: [previous])
        }
        return profile
    }

    /// Убирает фото профиля (остаются инициалы) и удаляет файл.
    public func removeAvatar() async throws -> UserProfile {
        guard let userID = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        let previous = try? await myProfile().avatarPath
        let profile = try await updateAvatarPath(nil, userID: userID)
        if let previous {
            _ = try? await supabase.storage.from(MediaPath.bucket).remove(paths: [previous])
        }
        return profile
    }

    /// Какие уведомления присылать и «тихие часы».
    public func updateNotificationSettings(_ settings: NotificationSettings) async throws -> UserProfile {
        guard let userID = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        return try await supabase
            .from("profiles")
            .update(settings)
            .eq("id", value: userID)
            .select()
            .single()
            .execute()
            .value
    }

    private func updateAvatarPath(_ path: String?, userID: UUID) async throws -> UserProfile {
        try await supabase
            .from("profiles")
            .update(AvatarChange(path: path))
            .eq("id", value: userID)
            .select()
            .single()
            .execute()
            .value
    }
}

/// `avatar_path` для `update`: `nil` кодируется как `null` — фото убирается.
struct AvatarChange: Encodable, Sendable {
    let path: String?

    enum CodingKeys: String, CodingKey {
        case path = "avatar_path"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path)
    }
}
