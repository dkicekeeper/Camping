import DaladaCore
import Foundation
import Supabase

// MARK: - Вкладка «Места»: подборки, поиск, сохранённые

extension BackendClient {
    /// Подборки одним ответом (RPC `places_discover`). `near` — где я; без неё «Рядом» пустая.
    public func placesDiscover(near: GeoPoint?) async throws -> PlaceDiscovery {
        try await supabase.rpc("places_discover", params: PointParams(near)).execute().value
    }

    /// Поиск и полные списки (RPC `places_search`): название, типы, сортировка.
    public func searchPlaces(
        _ query: PlaceQuery,
        near: GeoPoint?,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [PlaceItem] {
        let params = PlaceSearchParams(query: query, near: near, limit: limit, offset: offset)
        return try await supabase.rpc("places_search", params: params).execute().value
    }

    /// Все места подборки редакции (RPC `place_collection`).
    public func placeCollection(id: UUID, near: GeoPoint?) async throws -> [PlaceItem] {
        try await supabase
            .rpc("place_collection", params: CollectionParams(id: id, near: near))
            .execute()
            .value
    }

    /// Сохранённые места, свежие сверху (RPC `my_saved_places`).
    public func savedPlaces(near: GeoPoint?) async throws -> [PlaceItem] {
        try await supabase.rpc("my_saved_places", params: PointParams(near)).execute().value
    }

    /// Сохранить место или убрать из сохранённых (RPC `save_place`).
    public func setPlaceSaved(_ placeID: UUID, saved: Bool) async throws {
        try await supabase
            .rpc("save_place", params: SaveParams(place: placeID, saved: saved))
            .execute()
    }

    /// Сохранено ли место у меня (своя строка `saved_places`).
    public func isPlaceSaved(_ placeID: UUID) async throws -> Bool {
        let rows: [SavedRow] = try await supabase
            .from("saved_places")
            .select("place_id")
            .eq("place_id", value: placeID.uuidString)
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }
}

/// «Где я» для RPC: обе координаты или ни одной (тогда поля не отправляются).
struct PointParams: Encodable, Sendable {
    let lon: Double?
    let lat: Double?

    init(_ point: GeoPoint?) {
        lon = point?.longitude
        lat = point?.latitude
    }

    enum CodingKeys: String, CodingKey {
        case lon = "p_lon"
        case lat = "p_lat"
    }
}

struct PlaceSearchParams: Encodable, Sendable {
    let query: String?
    let types: [PlaceType]?
    let sort: PlaceSort?
    let lon: Double?
    let lat: Double?
    let limit: Int
    let offset: Int

    init(query: PlaceQuery, near: GeoPoint?, limit: Int, offset: Int) {
        let text = query.trimmedText
        self.query = text.isEmpty ? nil : text
        types = query.types.isEmpty ? nil : query.types.sorted { $0.rawValue < $1.rawValue }
        // «По расстоянию» без позиции сервер сам заменит на «по названию».
        sort = query.sort
        lon = near?.longitude
        lat = near?.latitude
        self.limit = limit
        self.offset = offset
    }

    enum CodingKeys: String, CodingKey {
        case query = "p_query"
        case types = "p_types"
        case sort = "p_sort"
        case lon = "p_lon"
        case lat = "p_lat"
        case limit = "p_limit"
        case offset = "p_offset"
    }
}

struct CollectionParams: Encodable, Sendable {
    let id: UUID
    let lon: Double?
    let lat: Double?

    init(id: UUID, near: GeoPoint?) {
        self.id = id
        lon = near?.longitude
        lat = near?.latitude
    }

    enum CodingKeys: String, CodingKey {
        case id = "p_collection"
        case lon = "p_lon"
        case lat = "p_lat"
    }
}

struct SaveParams: Encodable, Sendable {
    let place: UUID
    let saved: Bool

    enum CodingKeys: String, CodingKey {
        case place = "p_place"
        case saved = "p_saved"
    }
}

private struct SavedRow: Decodable, Sendable {
    let placeID: UUID

    enum CodingKeys: String, CodingKey {
        case placeID = "place_id"
    }
}
