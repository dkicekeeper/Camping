import DaladaCore
import Foundation
import Supabase

// MARK: - Картинки для Stories и Telegram

extension BackendClient {
    /// Данные для картинки своей поездки; `nil` — поездка не своя или удалена.
    public func tripShareCard(_ tripID: UUID) async throws -> TripShareCard? {
        let rows: [TripShareCard] = try await supabase
            .rpc("trip_share_card", params: ["p_trip": tripID])
            .execute()
            .value
        return rows.first
    }

    /// Данные для картинки своего улова; `nil` — улов не свой или удалён.
    public func catchShareCard(_ catchID: UUID) async throws -> CatchShareCard? {
        let rows: [CatchShareCard] = try await supabase
            .rpc("catch_share_card", params: ["p_catch": catchID])
            .execute()
            .value
        return rows.first
    }
}
