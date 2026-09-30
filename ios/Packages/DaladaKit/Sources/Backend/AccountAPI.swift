import DaladaCore
import Foundation
import Supabase

// MARK: - Удаление аккаунта

extension BackendClient {
    /// Удаляет свой аккаунт: сначала свои фото в бакете `media`, затем пользователя со всеми
    /// данными (RPC `delete_my_account`), потом сессию на телефоне. Без сети — ошибка, аккаунт цел.
    public func deleteMyAccount() async throws {
        guard let userID = supabase.auth.currentUser?.id else { throw AuthError.sessionMissing }
        let folder = userID.uuidString.lowercased()
        let bucket = supabase.storage.from("media")
        // Файлы лежат в папке автора; удаляем пачками, пока папка не опустеет.
        for _ in 0..<100 {
            let files = try await bucket.list(path: folder, options: SearchOptions(limit: 1000))
            let paths = files.map { "\(folder)/\($0.name)" }
            guard !paths.isEmpty else { break }
            let removed = try await bucket.remove(paths: paths)
            if removed.isEmpty || files.count < 1000 { break }
        }
        try await supabase.rpc("delete_my_account").execute()
        // Пользователя на сервере уже нет — выходим только на телефоне.
        try? await supabase.auth.signOut(scope: .local)
    }
}
