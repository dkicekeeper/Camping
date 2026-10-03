import DaladaCore
import Foundation
import Supabase

// MARK: - Достижения

extension BackendClient {
    /// Свои значки с прогрессом; заодно выдаёт заработанные с прошлого раза (RPC `my_achievements`).
    public func myAchievements() async throws -> [Achievement] {
        try await supabase.rpc("my_achievements").execute().value
    }

    /// Поздравление показано — значки больше не «новые».
    public func markAchievementsSeen() async throws {
        try await supabase.rpc("mark_achievements_seen").execute()
    }
}
