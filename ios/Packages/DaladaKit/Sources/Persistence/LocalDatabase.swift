import Foundation
import GRDB

/// Локальная база приложения (SQLite через GRDB): очередь отправки и кэш для работы без сети.
public final class LocalDatabase: Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// База в файле `Application Support/Dalada/dalada.sqlite`.
    public static func openDefault() throws -> LocalDatabase {
        let folder = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Dalada", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try open(at: folder.appendingPathComponent("dalada.sqlite"))
    }

    public static func open(at url: URL) throws -> LocalDatabase {
        try LocalDatabase(writer: DatabasePool(path: url.path))
    }

    /// База в памяти — для превью, тестов и на случай, если файл не открылся.
    public static func inMemory() throws -> LocalDatabase {
        try LocalDatabase(writer: DatabaseQueue())
    }

    public var outbox: OutboxStore { OutboxStore(writer: writer) }
    public var cache: CacheStore { CacheStore(writer: writer) }
    public var trips: TripStore { TripStore(writer: writer) }
    public var ownRecords: OwnRecordStore { OwnRecordStore(writer: writer) }

    /// Схема. Миграции только добавляются, как и на сервере.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            // Чекины, которые ещё не ушли на сервер.
            try db.create(table: "outbox_checkin") { t in
                t.primaryKey("id", .blob)
                t.column("owner_id", .blob).notNull().indexed()
                t.column("place_id", .blob).notNull()
                t.column("place_name", .text).notNull()
                t.column("at", .datetime).notNull()
                t.column("payload", .jsonText).notNull()
                t.column("status", .text).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("next_attempt_at", .datetime).notNull()
                t.column("last_error", .text)
            }
            // Фото этих чекинов (готовые JPEG).
            try db.create(table: "outbox_photo") { t in
                t.primaryKey("id", .blob)
                t.column("checkin_id", .blob).notNull().indexed()
                    .references("outbox_checkin", onDelete: .cascade)
                t.column("catch_id", .blob)
                t.column("position", .integer).notNull()
                t.column("full", .blob).notNull()
                t.column("thumbnail", .blob).notNull()
                t.column("width", .integer).notNull()
                t.column("height", .integer).notNull()
            }
            // Последние ответы сервера (JSON) — показываем, пока нет сети.
            try db.create(table: "cache_entry") { t in
                t.primaryKey("key", .text)
                t.column("value", .blob).notNull()
                t.column("updated_at", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2-trips") { db in
            // Идущая запись поездки (не больше одной).
            try db.create(table: "active_trip") { t in
                t.primaryKey("id", .blob)
                t.column("activity", .text).notNull()
                t.column("started_at", .datetime).notNull()
                t.column("state", .text).notNull()
            }
            // Точки трека — и идущей поездки, и поездок в очереди отправки. Пишутся сразу,
            // поэтому трек не теряется, если приложение закрыли или оно упало.
            try db.create(table: "track_point") { t in
                t.column("trip_id", .blob).notNull()
                t.column("seq", .integer).notNull()
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("altitude", .double)
                t.column("accuracy", .double).notNull()
                t.column("speed", .double)
                t.column("timestamp", .datetime).notNull()
                t.column("starts_segment", .boolean).notNull().defaults(to: false)
                t.primaryKey(["trip_id", "seq"])
            }
            // Законченные поездки, которые ещё не приняты сервером.
            try db.create(table: "outbox_trip") { t in
                t.primaryKey("id", .blob)
                t.column("owner_id", .blob).notNull().indexed()
                t.column("activity", .text).notNull()
                t.column("title", .text).notNull()
                t.column("note", .text).notNull()
                t.column("visibility", .text).notNull()
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime).notNull()
                t.column("status", .text).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("next_attempt_at", .datetime).notNull()
                t.column("last_error", .text)
            }
        }
        migrator.registerMigration("v3-own-lists") { db in
            // Свои записи (экипировка, чеклисты) в JSON; `is_dirty` — правка ещё не на сервере.
            try db.create(table: "own_record") { t in
                t.column("kind", .text).notNull()
                t.column("id", .blob).notNull()
                t.column("account", .text).notNull()
                t.column("payload", .blob).notNull()
                t.column("updated_at", .double).notNull()
                t.column("is_deleted", .boolean).notNull()
                t.column("is_dirty", .boolean).notNull()
                t.primaryKey(["kind", "id"])
            }
            try db.create(index: "own_record_account", on: "own_record", columns: ["account", "kind"])
            // До какого `synced_at` изменения с сервера уже получены.
            try db.create(table: "own_sync_cursor") { t in
                t.column("account", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("synced_at", .double).notNull()
                t.primaryKey(["account", "kind"])
            }
        }
        return migrator
    }
}
