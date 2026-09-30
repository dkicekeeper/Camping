import DaladaCore
import Foundation
import GRDB

/// Идущая запись поездки.
public struct ActiveTrip: Equatable, Sendable {
    public enum State: String, Sendable {
        case recording
        case paused
    }

    public let id: UUID
    public let activity: TripActivity
    public let startedAt: Date
    public let state: State
    public let points: [TrackPoint]
}

/// Запись поездки: каждая точка сразу на диске. После финиша поездка уходит в очередь отправки.
public struct TripStore: Sendable {
    let writer: any DatabaseWriter

    /// Начинает запись. Незаконченная предыдущая запись удаляется.
    public func start(id: UUID, activity: TripActivity, at date: Date) async throws {
        try await writer.write { db in
            try Self.deleteActive(db)
            try ActiveTripRecord(id: id, activity: activity.rawValue, startedAt: date, state: ActiveTrip.State.recording.rawValue)
                .insert(db)
        }
    }

    public func append(_ point: TrackPoint, to tripID: UUID) async throws {
        try await writer.write { db in
            let seq = try Int.fetchOne(
                db,
                sql: "SELECT coalesce(max(seq), 0) + 1 FROM track_point WHERE trip_id = ?",
                arguments: [tripID]
            ) ?? 1
            try TrackPointRecord(point, tripID: tripID, seq: seq).insert(db)
        }
    }

    public func setState(_ state: ActiveTrip.State) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE active_trip SET state = ?", arguments: [state.rawValue])
        }
    }

    /// Незаконченная запись (после перезапуска приложения) — с точками.
    public func active() async throws -> ActiveTrip? {
        try await writer.read { db in
            guard let record = try ActiveTripRecord.fetchOne(db) else { return nil }
            return ActiveTrip(
                id: record.id,
                activity: TripActivity(rawValue: record.activity) ?? .other,
                startedAt: record.startedAt,
                state: ActiveTrip.State(rawValue: record.state) ?? .paused,
                points: try TrackPointRecord.points(of: record.id, in: db)
            )
        }
    }

    /// «Удалить поездку» — запись и точки стираются.
    public func discardActive() async throws {
        try await writer.write { db in try Self.deleteActive(db) }
    }

    /// Финиш: поездка переходит в очередь отправки (точки остаются), активной записи больше нет.
    public func finishActive(
        owner: UUID,
        title: String,
        note: String,
        visibility: Visibility,
        activity: TripActivity,
        endedAt: Date,
        now: Date
    ) async throws {
        try await writer.write { db in
            guard let active = try ActiveTripRecord.fetchOne(db) else { return }
            try OutboxTripRecord(
                id: active.id,
                ownerID: owner,
                activity: activity.rawValue,
                title: title,
                note: note,
                visibility: visibility.rawValue,
                startedAt: active.startedAt,
                endedAt: max(endedAt, active.startedAt),
                status: OutboxStatus.pending.rawValue,
                attempts: 0,
                nextAttemptAt: now,
                lastError: nil
            ).insert(db)
            try ActiveTripRecord.deleteAll(db)
        }
    }

    private static func deleteActive(_ db: Database) throws {
        if let active = try ActiveTripRecord.fetchOne(db) {
            try db.execute(sql: "DELETE FROM track_point WHERE trip_id = ?", arguments: [active.id])
        }
        try ActiveTripRecord.deleteAll(db)
    }
}

// MARK: - Записи

struct ActiveTripRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "active_trip"

    var id: UUID
    var activity: String
    var startedAt: Date
    var state: String

    enum CodingKeys: String, CodingKey {
        case id
        case activity
        case startedAt = "started_at"
        case state
    }
}

struct TrackPointRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "track_point"

    var tripID: UUID
    var seq: Int
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var accuracy: Double
    var speed: Double?
    var timestamp: Date
    var startsSegment: Bool

    enum CodingKeys: String, CodingKey {
        case tripID = "trip_id"
        case seq
        case latitude
        case longitude
        case altitude
        case accuracy
        case speed
        case timestamp
        case startsSegment = "starts_segment"
    }

    init(_ point: TrackPoint, tripID: UUID, seq: Int) {
        self.tripID = tripID
        self.seq = seq
        latitude = point.latitude
        longitude = point.longitude
        altitude = point.altitude
        accuracy = point.horizontalAccuracy
        speed = point.speed
        timestamp = point.timestamp
        startsSegment = point.startsSegment
    }

    var point: TrackPoint {
        TrackPoint(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: accuracy,
            speed: speed,
            timestamp: timestamp,
            startsSegment: startsSegment
        )
    }

    static func points(of tripID: UUID, in db: Database) throws -> [TrackPoint] {
        try TrackPointRecord
            .filter(Column("trip_id") == tripID)
            .order(Column("seq"))
            .fetchAll(db)
            .map(\.point)
    }
}

struct OutboxTripRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "outbox_trip"

    var id: UUID
    var ownerID: UUID
    var activity: String
    var title: String
    var note: String
    var visibility: String
    var startedAt: Date
    var endedAt: Date
    var status: String
    var attempts: Int
    var nextAttemptAt: Date
    var lastError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case activity
        case title
        case note
        case visibility
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case status
        case attempts
        case nextAttemptAt = "next_attempt_at"
        case lastError = "last_error"
    }

    func draft(points: [TrackPoint]) -> TripDraft {
        TripDraft(
            id: id,
            activity: TripActivity(rawValue: activity) ?? .other,
            title: title,
            note: note,
            visibility: Visibility(rawValue: visibility) ?? .private,
            startedAt: startedAt,
            endedAt: endedAt,
            points: points
        )
    }

    var pending: PendingTrip {
        PendingTrip(
            id: id,
            activity: TripActivity(rawValue: activity) ?? .other,
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            state: status == OutboxStatus.failed.rawValue ? .failed(lastError ?? "") : .waiting
        )
    }
}
