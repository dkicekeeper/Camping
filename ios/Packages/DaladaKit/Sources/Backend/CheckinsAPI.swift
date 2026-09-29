import DaladaCore
import Foundation
import Supabase

// MARK: - Чекины, уловы, отчёты

extension BackendClient {
    /// Справочник рыб, по порядку сортировки.
    public func fishSpecies() async throws -> [FishSpecies] {
        try await supabase
            .from("fish_species")
            .select()
            .order("sort_order")
            .execute()
            .value
    }

    /// Свежие отчёты места, которые видит пользователь (RPC `place_reports`).
    public func placeReports(placeID: UUID, limit: Int = 20) async throws -> [PlaceReport] {
        try await supabase
            .rpc("place_reports", params: PlaceReportsParams(placeID: placeID, limit: limit))
            .execute()
            .value
    }

    /// Свои уловы, новые сверху (RPC `my_catches`).
    public func myCatches(limit: Int = 50) async throws -> [MyCatch] {
        try await supabase
            .rpc("my_catches", params: ["p_limit": limit])
            .execute()
            .value
    }

    /// Создаёт чекин и его уловы. ID задаёт клиент: при повторной отправке уже созданные
    /// записи упираются в первичный ключ (23505) — это считается успехом.
    public func createCheckin(_ draft: CheckinDraft) async throws {
        try await insertIgnoringDuplicates(into: "checkins", CheckinInsert(draft))
        guard !draft.catches.isEmpty else { return }
        let catches = draft.catches.map { CatchInsert($0, checkinID: draft.id, visibility: draft.visibility) }
        try await insertIgnoringDuplicates(into: "catches", catches)
    }

    private func insertIgnoringDuplicates(into table: String, _ values: some Encodable & Sendable) async throws {
        do {
            try await supabase.from(table).insert(values, returning: .minimal).execute()
        } catch let error as PostgrestError where error.code == "23505" {
            return
        }
    }
}

// MARK: - Параметры и строки для вставки

struct PlaceReportsParams: Encodable, Sendable {
    let placeID: UUID
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case placeID = "p_place"
        case limit = "p_limit"
    }
}

/// Строка `checkins`. Необязательные поля кодируются явным `null`.
struct CheckinInsert: Encodable, Sendable {
    let id: UUID
    let placeID: UUID
    let geom: String?
    let conditions: CheckinConditions
    let note: String?
    let visibility: Visibility

    init(_ draft: CheckinDraft) {
        id = draft.id
        placeID = draft.placeID
        geom = draft.deviceLocation.map { "SRID=4326;POINT(\($0.longitude) \($0.latitude))" }
        conditions = draft.conditions
        note = draft.trimmedNote.isEmpty ? nil : draft.trimmedNote
        visibility = draft.visibility
    }

    enum CodingKeys: String, CodingKey {
        case id
        case placeID = "place_id"
        case geom
        case conditions
        case note
        case visibility
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(placeID, forKey: .placeID)
        try c.encode(geom, forKey: .geom)
        try c.encode(conditions, forKey: .conditions)
        try c.encode(note, forKey: .note)
        try c.encode(visibility, forKey: .visibility)
    }
}

/// Строка `catches`. При пакетной вставке PostgREST требует одинаковые ключи у всех объектов,
/// поэтому необязательные поля кодируются явным `null`, а не пропускаются.
struct CatchInsert: Encodable, Sendable {
    let id: UUID
    let checkinID: UUID
    let speciesID: String
    let weightGrams: Int?
    let lengthMillimeters: Int?
    let count: Int
    let method: FishingMethod?
    let bait: String?
    let released: Bool
    let hideSize: Bool
    let visibility: Visibility

    init(_ draft: CatchDraft, checkinID: UUID, visibility: Visibility) {
        id = draft.id
        self.checkinID = checkinID
        speciesID = draft.speciesID
        weightGrams = draft.weightGrams
        lengthMillimeters = draft.lengthMillimeters
        count = draft.count
        method = draft.method
        let bait = draft.bait.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bait = bait.isEmpty ? nil : bait
        released = draft.released
        hideSize = draft.hideSize
        self.visibility = visibility
    }

    enum CodingKeys: String, CodingKey {
        case id
        case checkinID = "checkin_id"
        case speciesID = "species_id"
        case weightGrams = "weight_g"
        case lengthMillimeters = "length_mm"
        case count
        case method
        case bait
        case released
        case hideSize = "hide_size"
        case visibility
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(checkinID, forKey: .checkinID)
        try c.encode(speciesID, forKey: .speciesID)
        try c.encode(weightGrams, forKey: .weightGrams)
        try c.encode(lengthMillimeters, forKey: .lengthMillimeters)
        try c.encode(count, forKey: .count)
        try c.encode(method, forKey: .method)
        try c.encode(bait, forKey: .bait)
        try c.encode(released, forKey: .released)
        try c.encode(hideSize, forKey: .hideSize)
        try c.encode(visibility, forKey: .visibility)
    }
}
