import DaladaCore
import Foundation
import Supabase

// MARK: - Места

extension BackendClient {
    /// Места в области карты с учётом видимости и огрубления (RPC `places_in_bbox`).
    public func places(in box: GeoBoundingBox, limit: Int = 500) async throws -> [PlaceSummary] {
        let area = box.clamped()
        let params = BoundingBoxParams(
            minLon: area.minLongitude,
            minLat: area.minLatitude,
            maxLon: area.maxLongitude,
            maxLat: area.maxLatitude,
            maxResults: limit
        )
        return try await supabase.rpc("places_in_bbox", params: params).execute().value
    }

    /// Свои места любой видимости, включая места на модерации (RPC `my_places`).
    public func myPlaces() async throws -> [PlaceSummary] {
        try await supabase.rpc("my_places").execute().value
    }

    /// Карточка места; `nil`, если места нет или оно не видно (RPC `place_card`).
    public func placeDetails(id: UUID) async throws -> PlaceDetails? {
        let rows: [PlaceDetails] = try await supabase
            .rpc("place_card", params: ["p_id": id.uuidString])
            .execute()
            .value
        return rows.first
    }

    /// Создаёт место. ID задаёт клиент: повторная отправка того же черновика упрётся в
    /// первичный ключ (23505) — это значит, что место уже создано.
    ///
    /// Не `upsert`: `ON CONFLICT DO UPDATE` требует права менять `id`, которого у клиента нет.
    public func createPlace(_ draft: PlaceDraft) async throws {
        do {
            try await supabase
                .from("places")
                .insert(PlaceInsert(draft), returning: .minimal)
                .execute()
        } catch let error as PostgrestError where error.code == "23505" {
            return
        }
    }
}

/// Строка для вставки в `places`. Координаты — EWKT: так PostGIS принимает их из JSON.
struct PlaceInsert: Encodable, Sendable {
    let id: UUID
    let type: PlaceType
    let name: String
    let description: String?
    let geom: String
    let visibility: Visibility
    let approximate: Bool

    init(_ draft: PlaceDraft) {
        id = draft.id
        type = draft.type
        name = draft.trimmedName
        description = draft.trimmedDescription.isEmpty ? nil : draft.trimmedDescription
        geom = "SRID=4326;POINT(\(draft.coordinate.longitude) \(draft.coordinate.latitude))"
        visibility = draft.visibility
        approximate = draft.effectiveApproximate
    }
}
