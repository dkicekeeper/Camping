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

// MARK: - Правка места

extension BackendClient {
    /// Своё место для правки (строка `places`); `nil` — не моё или удалено.
    public func ownPlace(id: UUID) async throws -> OwnPlaceDraft? {
        let rows: [OwnPlaceDraft] = try await supabase
            .from("places")
            .select("type,name,description,visibility,approximate,attributes")
            .eq("id", value: id.uuidString)
            .is("deleted_at", value: nil)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Изменить своё место: название, тип, описание, видимость, «Информацию». Публичное место у
    /// новых авторов снова уходит на проверку — это решает база.
    public func updatePlace(id: UUID, _ draft: OwnPlaceDraft) async throws {
        try await supabase
            .from("places")
            .update(PlaceUpdate(draft), returning: .minimal)
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Предложить правку чужого публичного места или сообщить о проблеме (RPC
    /// `suggest_place_change`). Повторное предложение того же вида обновляет открытое.
    public func suggestPlaceChange(
        placeID: UUID,
        kind: PlaceSuggestionKind,
        changes: PlaceChanges?,
        note: String?
    ) async throws {
        try await supabase
            .rpc("suggest_place_change", params: SuggestParams(place: placeID, kind: kind, changes: changes, note: note))
            .execute()
    }

    /// Мои предложения к месту, которые ещё на проверке.
    public func openPlaceSuggestions(placeID: UUID) async throws -> Set<PlaceSuggestionKind> {
        let rows: [SuggestionRow] = try await supabase
            .from("place_suggestions")
            .select("kind")
            .eq("place_id", value: placeID.uuidString)
            .eq("status", value: "open")
            .execute()
            .value
        return Set(rows.compactMap { PlaceSuggestionKind(rawValue: $0.kind) })
    }
}

/// Изменения своего места. Пустое описание — `null` (явно, чтобы стереть прежнее).
struct PlaceUpdate: Encodable, Sendable {
    let type: PlaceType
    let name: String
    let description: String?
    let attributes: PlaceAttributes
    let visibility: Visibility
    let approximate: Bool

    init(_ draft: OwnPlaceDraft) {
        type = draft.fields.type
        name = draft.fields.trimmedName
        description = draft.fields.trimmedDescription.isEmpty ? nil : draft.fields.trimmedDescription
        attributes = draft.fields.attributes.normalized
        visibility = draft.visibility
        approximate = draft.effectiveApproximate
    }

    enum CodingKeys: String, CodingKey {
        case type, name, description, attributes, visibility, approximate
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(name, forKey: .name)
        if let description {
            try c.encode(description, forKey: .description)
        } else {
            try c.encodeNil(forKey: .description)
        }
        try c.encode(attributes, forKey: .attributes)
        try c.encode(visibility, forKey: .visibility)
        try c.encode(approximate, forKey: .approximate)
    }
}

struct SuggestParams: Encodable, Sendable {
    let place: UUID
    let kind: PlaceSuggestionKind
    let changes: PlaceChanges?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case place = "p_place"
        case kind = "p_kind"
        case changes = "p_changes"
        case note = "p_note"
    }
}

private struct SuggestionRow: Decodable, Sendable {
    let kind: String
}
