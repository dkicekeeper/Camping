import DaladaCore
import Foundation
import GRDB

/// Свои записи (экипировка, чеклисты) на телефоне: работают без сети и без аккаунта.
/// Каждая правка сразу на диске и помечена «не отправлено», пока сервер её не принял.
/// `account` — id пользователя или `guest`: у каждого аккаунта на телефоне свои списки.
public struct OwnRecordStore: Sendable {
    let writer: any DatabaseWriter

    public static let guestAccount = "guest"

    /// JSON записи с ключами по алфавиту — одинаковые записи дают одинаковые байты.
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    public static func account(for userID: UUID?) -> String {
        userID?.uuidString.lowercased() ?? guestAccount
    }

    /// Все записи аккаунта (без удалённых, если не попросить).
    public func all<R: SyncedRecord>(_ type: R.Type, account: String, includeDeleted: Bool = false) async throws -> [R] {
        let rows = try await writer.read { db in
            try Data.fetchAll(
                db,
                sql: """
                SELECT payload FROM own_record
                 WHERE kind = ? AND account = ? AND (? OR is_deleted = 0)
                 ORDER BY updated_at DESC
                """,
                arguments: [R.recordKind, account, includeDeleted]
            )
        }
        let decoder = JSONDecoder()
        // Запись, которая не разобралась (формат устарел), пропускается.
        return rows.compactMap { try? decoder.decode(R.self, from: $0) }
    }

    /// Своя правка: сохраняется и ждёт отправки. Более старая версия (запись успели поправить
    /// ещё раз или пришла правка с сервера) не затирает сохранённую.
    public func save<R: SyncedRecord>(_ record: R, account: String) async throws {
        let payload = try Self.encoder().encode(record)
        try await writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO own_record (kind, id, account, payload, updated_at, is_deleted, is_dirty)
                VALUES (?, ?, ?, ?, ?, ?, 1)
                ON CONFLICT (kind, id) DO UPDATE SET
                  account = excluded.account, payload = excluded.payload, updated_at = excluded.updated_at,
                  is_deleted = excluded.is_deleted, is_dirty = 1
                WHERE excluded.updated_at >= own_record.updated_at
                """,
                arguments: [R.recordKind, record.id, account, payload, record.updatedAt.timeIntervalSince1970,
                            record.isDeleted]
            )
        }
    }

    /// Правки, которые ещё не приняты сервером.
    public func dirty<R: SyncedRecord>(_ type: R.Type, account: String) async throws -> [R] {
        let rows = try await writer.read { db in
            try Data.fetchAll(
                db,
                sql: "SELECT payload FROM own_record WHERE kind = ? AND account = ? AND is_dirty = 1",
                arguments: [R.recordKind, account]
            )
        }
        let decoder = JSONDecoder()
        return rows.compactMap { try? decoder.decode(R.self, from: $0) }
    }

    /// Сервер принял эти версии. Если запись успели поправить ещё раз, пока шла отправка,
    /// новая правка остаётся неотправленной.
    public func markSynced<R: SyncedRecord>(_ records: [R], account: String) async throws {
        try await writer.write { db in
            for record in records {
                try db.execute(
                    sql: """
                    UPDATE own_record SET is_dirty = 0
                     WHERE kind = ? AND id = ? AND account = ? AND updated_at = ?
                    """,
                    arguments: [R.recordKind, record.id, account, record.updatedAt.timeIntervalSince1970]
                )
            }
        }
    }

    /// Записи с сервера (в том числе с других устройств). Своя неотправленная правка новее
    /// серверной — остаётся. Возвращает, сколько записей изменилось.
    @discardableResult
    public func applyRemote<R: SyncedRecord>(_ records: [R], account: String) async throws -> Int {
        let encoder = Self.encoder()
        let payloads = try records.map { try encoder.encode($0) }
        return try await writer.write { db in
            var changed = 0
            for (record, payload) in zip(records, payloads) {
                let local = try Row.fetchOne(
                    db,
                    sql: "SELECT updated_at, is_dirty, payload FROM own_record WHERE kind = ? AND id = ?",
                    arguments: [R.recordKind, record.id]
                )
                if let local {
                    let localUpdatedAt = Date(timeIntervalSince1970: local["updated_at"] as Double)
                    let localIsDirty = local["is_dirty"] as Bool
                    if SyncMerge.keepsLocal(localUpdatedAt: localUpdatedAt, localIsDirty: localIsDirty,
                                            remoteUpdatedAt: record.updatedAt) {
                        continue
                    }
                    if (local["payload"] as Data) != payload {
                        changed += 1
                    }
                } else {
                    changed += 1
                }
                try Self.upsert(db, kind: R.recordKind, id: record.id, account: account, payload: payload,
                                updatedAt: record.updatedAt, isDeleted: record.isDeleted, isDirty: false)
            }
            return changed
        }
    }

    /// С какого момента забирать изменения с сервера (`synced_at` последней полученной записи).
    public func cursor(kind: String, account: String) async throws -> Date? {
        try await writer.read { db in
            try Double.fetchOne(
                db,
                sql: "SELECT synced_at FROM own_sync_cursor WHERE account = ? AND kind = ?",
                arguments: [account, kind]
            )
        }
        .map { Date(timeIntervalSince1970: $0) }
    }

    public func setCursor(_ date: Date, kind: String, account: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO own_sync_cursor (account, kind, synced_at) VALUES (?, ?, ?)",
                arguments: [account, kind, date.timeIntervalSince1970]
            )
        }
    }

    /// Списки гостя переходят в аккаунт после входа (и уходят на сервер). Возвращает число записей.
    @discardableResult
    public func adopt(from source: String, into target: String) async throws -> Int {
        guard source != target else { return 0 }
        return try await writer.write { db in
            try db.execute(
                sql: "UPDATE own_record SET account = ?, is_dirty = 1 WHERE account = ?",
                arguments: [target, source]
            )
            return db.changesCount
        }
    }

    /// После выхода из аккаунта: его списки на телефоне стираются, кроме неотправленных правок —
    /// они уйдут, когда этот пользователь войдёт снова.
    public func removeSynced(account: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM own_record WHERE account = ? AND is_dirty = 0", arguments: [account])
            try db.execute(sql: "DELETE FROM own_sync_cursor WHERE account = ?", arguments: [account])
        }
    }

    private static func upsert(
        _ db: Database,
        kind: String,
        id: UUID,
        account: String,
        payload: Data,
        updatedAt: Date,
        isDeleted: Bool,
        isDirty: Bool
    ) throws {
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO own_record (kind, id, account, payload, updated_at, is_deleted, is_dirty)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [kind, id, account, payload, updatedAt.timeIntervalSince1970, isDeleted, isDirty]
        )
    }
}
