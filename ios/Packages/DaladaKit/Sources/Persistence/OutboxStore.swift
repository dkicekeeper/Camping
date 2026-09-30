import DaladaCore
import Foundation
import GRDB

/// Очередь отправки: чекины (с уловами и фото) и поездки (с треком), созданные на телефоне
/// и ещё не принятые сервером.
/// Запись удаляется, только когда сервер подтвердил приём.
public struct OutboxStore: Sendable {
    let writer: any DatabaseWriter

    /// Кладёт чекин в очередь целиком (одной транзакцией вместе с фото). Отправить — сразу.
    public func enqueue(_ draft: CheckinDraft, owner: UUID, placeName: String, now: Date) async throws {
        try await writer.write { db in
            try OutboxCheckinRecord(
                id: draft.id,
                ownerID: owner,
                placeID: draft.placeID,
                placeName: placeName,
                at: draft.at,
                payload: StoredCheckin(draft),
                status: .pending,
                attempts: 0,
                nextAttemptAt: now,
                lastError: nil
            ).insert(db)
            for (position, upload) in draft.photoUploads.enumerated() {
                try OutboxPhotoRecord(upload, checkinID: draft.id, position: position).insert(db)
            }
        }
    }

    /// Чекины, которые пора отправить (с фото), по времени создания.
    public func due(owner: UUID, now: Date, limit: Int = 1) async throws -> [CheckinDraft] {
        try await writer.read { db in
            let records = try OutboxCheckinRecord
                .filter(Column("owner_id") == owner)
                .filter(Column("status") == OutboxStatus.pending.rawValue)
                .filter(Column("next_attempt_at") <= now)
                .order(Column("at"), Column("id"))
                .limit(limit)
                .fetchAll(db)
            return try records.map { record in
                let photos = try OutboxPhotoRecord
                    .filter(Column("checkin_id") == record.id)
                    .order(Column("position"))
                    .fetchAll(db)
                return record.draft(photos: photos)
            }
        }
    }

    /// Все записи пользователя для интерфейса — без самих фото.
    public func pending(owner: UUID) async throws -> [PendingCheckin] {
        try await writer.read { db in
            let records = try OutboxCheckinRecord
                .filter(Column("owner_id") == owner)
                .order(Column("at").desc)
                .fetchAll(db)
            return try records.map { record in
                let photoCount = try OutboxPhotoRecord
                    .filter(Column("checkin_id") == record.id)
                    .fetchCount(db)
                return record.pending(photoCount: photoCount)
            }
        }
    }

    /// Поездки, которые пора отправить (с точками трека), по времени начала.
    public func dueTrips(owner: UUID, now: Date, limit: Int = 1) async throws -> [TripDraft] {
        try await writer.read { db in
            let records = try OutboxTripRecord
                .filter(Column("owner_id") == owner)
                .filter(Column("status") == OutboxStatus.pending.rawValue)
                .filter(Column("next_attempt_at") <= now)
                .order(Column("started_at"), Column("id"))
                .limit(limit)
                .fetchAll(db)
            return try records.map { record in
                record.draft(points: try TrackPointRecord.points(of: record.id, in: db))
            }
        }
    }

    /// Поездки пользователя в очереди — для интерфейса, без точек.
    public func pendingTrips(owner: UUID) async throws -> [PendingTrip] {
        try await writer.read { db in
            try OutboxTripRecord
                .filter(Column("owner_id") == owner)
                .order(Column("started_at").desc)
                .fetchAll(db)
                .map(\.pending)
        }
    }

    // MARK: Общее для чекинов и поездок (id уникальны, запись ищется в обеих таблицах)

    /// Сервер принял — убираем из очереди (фото чекина — каскадом, точки поездки — здесь).
    public func remove(_ id: UUID) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM outbox_checkin WHERE id = ?", arguments: [id])
            if try Int.fetchOne(db, sql: "SELECT count(*) FROM outbox_trip WHERE id = ?", arguments: [id]) ?? 0 > 0 {
                try db.execute(sql: "DELETE FROM track_point WHERE trip_id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM outbox_trip WHERE id = ?", arguments: [id])
            }
        }
    }

    /// Неудачная попытка: следующая — через паузу по `RetryPolicy`. Возвращает число попыток.
    @discardableResult
    public func recordFailedAttempt(_ id: UUID, error: String?, now: Date) async throws -> Int {
        try await writer.write { db in
            for table in Self.tables {
                guard let attempts = try Int.fetchOne(
                    db, sql: "SELECT attempts FROM \(table) WHERE id = ?", arguments: [id]
                ) else { continue }
                let next = attempts + 1
                try db.execute(
                    sql: "UPDATE \(table) SET attempts = ?, last_error = ?, next_attempt_at = ? WHERE id = ?",
                    arguments: [next, error, now.addingTimeInterval(RetryPolicy.delay(afterAttempt: next)), id]
                )
                return next
            }
            return 0
        }
    }

    /// Больше не отправляем сами — ждём решения пользователя («Повторить» или «Удалить»).
    public func markFailed(_ id: UUID, error: String) async throws {
        try await writer.write { db in
            for table in Self.tables {
                try db.execute(
                    sql: "UPDATE \(table) SET status = ?, last_error = ? WHERE id = ?",
                    arguments: [OutboxStatus.failed.rawValue, error, id]
                )
            }
        }
    }

    /// «Повторить»: возвращаем в очередь со сброшенным счётчиком.
    public func requeue(_ id: UUID, now: Date) async throws {
        try await writer.write { db in
            for table in Self.tables {
                try db.execute(
                    sql: "UPDATE \(table) SET status = ?, attempts = 0, last_error = NULL, next_attempt_at = ? WHERE id = ?",
                    arguments: [OutboxStatus.pending.rawValue, now, id]
                )
            }
        }
    }

    /// Появилась сеть или приложение открыли: всё ждущее — отправлять сейчас, не дожидаясь паузы.
    public func makeDue(owner: UUID, now: Date) async throws {
        try await writer.write { db in
            for table in Self.tables {
                try db.execute(
                    sql: "UPDATE \(table) SET next_attempt_at = ? WHERE owner_id = ? AND status = ?",
                    arguments: [now, owner, OutboxStatus.pending.rawValue]
                )
            }
        }
    }

    /// Когда следующая попытка (для таймера).
    public func nextAttemptDate(owner: UUID) async throws -> Date? {
        try await writer.read { db in
            try Date.fetchOne(
                db,
                sql: """
                SELECT min(next_attempt_at) FROM (
                  SELECT next_attempt_at FROM outbox_checkin WHERE owner_id = ? AND status = ?
                  UNION ALL
                  SELECT next_attempt_at FROM outbox_trip WHERE owner_id = ? AND status = ?
                )
                """,
                arguments: [owner, OutboxStatus.pending.rawValue, owner, OutboxStatus.pending.rawValue]
            )
        }
    }

    private static let tables = ["outbox_checkin", "outbox_trip"]
}

// MARK: - Записи

enum OutboxStatus: String, Codable, Sendable, DatabaseValueConvertible {
    case pending
    case failed
}

struct OutboxCheckinRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "outbox_checkin"

    var id: UUID
    var ownerID: UUID
    var placeID: UUID
    var placeName: String
    var at: Date
    var payload: StoredCheckin
    var status: OutboxStatus
    var attempts: Int
    var nextAttemptAt: Date
    var lastError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case placeID = "place_id"
        case placeName = "place_name"
        case at
        case payload
        case status
        case attempts
        case nextAttemptAt = "next_attempt_at"
        case lastError = "last_error"
    }

    func draft(photos: [OutboxPhotoRecord]) -> CheckinDraft {
        var catches = payload.catches.map(\.draft)
        for photo in photos {
            guard let catchID = photo.catchID,
                  let index = catches.firstIndex(where: { $0.id == catchID })
            else { continue }
            catches[index].photo = photo.photo
        }
        return CheckinDraft(
            id: id,
            placeID: placeID,
            at: at,
            conditions: payload.conditions,
            note: payload.note,
            visibility: payload.visibility,
            catches: catches,
            photos: photos.filter { $0.catchID == nil }.map(\.photo),
            deviceLocation: payload.deviceLocation
        )
    }

    func pending(photoCount: Int) -> PendingCheckin {
        PendingCheckin(
            id: id,
            placeID: placeID,
            placeName: placeName,
            at: at,
            conditions: payload.conditions,
            note: payload.note,
            catches: payload.catches.map(\.draft),
            photoCount: photoCount,
            state: status == .failed ? .failed(lastError ?? "") : .waiting
        )
    }
}

struct OutboxPhotoRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "outbox_photo"

    var id: UUID
    var checkinID: UUID
    var catchID: UUID?
    var position: Int
    var full: Data
    var thumbnail: Data
    var width: Int
    var height: Int

    enum CodingKeys: String, CodingKey {
        case id
        case checkinID = "checkin_id"
        case catchID = "catch_id"
        case position
        case full
        case thumbnail
        case width
        case height
    }

    init(_ upload: PhotoUpload, checkinID: UUID, position: Int) {
        id = upload.photo.id
        self.checkinID = checkinID
        catchID = upload.catchID
        self.position = position
        full = upload.photo.full
        thumbnail = upload.photo.thumbnail
        width = upload.photo.width
        height = upload.photo.height
    }

    var photo: PhotoDraft {
        PhotoDraft(id: id, full: full, thumbnail: thumbnail, width: width, height: height)
    }
}

/// Черновик чекина без фото — хранится в `outbox_checkin.payload` (JSON).
struct StoredCheckin: Codable, Sendable {
    var conditions: CheckinConditions
    var note: String
    var visibility: Visibility
    var deviceLocation: GeoPoint?
    var catches: [StoredCatch]

    init(_ draft: CheckinDraft) {
        conditions = draft.conditions
        note = draft.note
        visibility = draft.visibility
        deviceLocation = draft.deviceLocation
        catches = draft.catches.map(StoredCatch.init)
    }
}

struct StoredCatch: Codable, Sendable {
    var id: UUID
    var speciesID: String
    var weightKg: Double?
    var lengthCm: Double?
    var count: Int
    var method: FishingMethod?
    var bait: String
    var released: Bool
    var hideSize: Bool

    init(_ draft: CatchDraft) {
        id = draft.id
        speciesID = draft.speciesID
        weightKg = draft.weightKg
        lengthCm = draft.lengthCm
        count = draft.count
        method = draft.method
        bait = draft.bait
        released = draft.released
        hideSize = draft.hideSize
    }

    var draft: CatchDraft {
        CatchDraft(
            id: id,
            speciesID: speciesID,
            weightKg: weightKg,
            lengthCm: lengthCm,
            count: count,
            method: method,
            bait: bait,
            released: released,
            hideSize: hideSize
        )
    }
}
