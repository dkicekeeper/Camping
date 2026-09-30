import DaladaCore
import Foundation
import Supabase

// MARK: - Поездки

extension BackendClient {
    /// Колонки поездки для списка — без трека.
    static let tripColumns = "id,activity,title,note,started_at,ended_at,moving_seconds,distance_m,elevation_gain_m,max_speed_mps,visibility"

    /// Свои поездки, новые сверху.
    public func myTrips(limit: Int = 50) async throws -> [TripSummary] {
        try await supabase
            .from("trips")
            .select(Self.tripColumns)
            .is("deleted_at", value: nil)
            .order("started_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Своя поездка с треком. `nil` — не найдена (удалена или чужая).
    public func tripDetails(id: UUID) async throws -> TripDetails? {
        let rows: [TripDetails] = try await supabase
            .from("trips")
            .select(Self.tripColumns + ",track")
            .eq("id", value: id)
            .is("deleted_at", value: nil)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Свои чекины за время поездки (RPC `my_trip_checkins`).
    public func tripCheckins(tripID: UUID) async throws -> [TripCheckin] {
        try await supabase
            .rpc("my_trip_checkins", params: ["p_trip": tripID])
            .execute()
            .value
    }

    /// Сохраняет поездку с треком. ID задаёт телефон: повтор после сбоя не создаёт дубль.
    public func createTrip(_ draft: TripDraft) async throws {
        do {
            try await supabase.from("trips").insert(TripInsert(draft), returning: .minimal).execute()
        } catch let error as PostgrestError where error.code == "23505" {
            return
        }
    }
}

/// Строка `trips`. Итоги считает телефон по тем же точкам, что уходят в трек.
struct TripInsert: Encodable, Sendable {
    let draft: TripDraft
    let stats: TrackStats

    init(_ draft: TripDraft) {
        self.draft = draft
        stats = draft.stats
    }

    enum CodingKeys: String, CodingKey {
        case id
        case activity
        case title
        case note
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case movingSeconds = "moving_seconds"
        case distanceM = "distance_m"
        case elevationGainM = "elevation_gain_m"
        case maxSpeedMps = "max_speed_mps"
        case track
        case visibility
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(draft.id, forKey: .id)
        try c.encode(draft.activity, forKey: .activity)
        try c.encode(draft.trimmedTitle, forKey: .title)
        let note = draft.trimmedNote
        try c.encode(note.isEmpty ? nil : note, forKey: .note)
        try c.encode(PostgresTimestamp.string(draft.startedAt), forKey: .startedAt)
        try c.encode(PostgresTimestamp.string(draft.endedAt), forKey: .endedAt)
        try c.encode(Int(stats.movingSeconds.rounded()), forKey: .movingSeconds)
        try c.encode(Int(stats.distanceM.rounded()), forKey: .distanceM)
        try c.encode(Int(stats.elevationGainM.rounded()), forKey: .elevationGainM)
        try c.encode(stats.maxSpeedMps > 0 ? stats.maxSpeedMps : nil, forKey: .maxSpeedMps)
        try c.encode(TrackEncoding.ewkt(draft.points), forKey: .track)
        try c.encode(draft.visibility, forKey: .visibility)
    }
}
