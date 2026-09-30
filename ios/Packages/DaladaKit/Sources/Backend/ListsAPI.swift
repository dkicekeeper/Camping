import DaladaCore
import Foundation
import Supabase

// MARK: - Экипировка и чеклисты

/// Своя запись с сервера и когда сервер её принял (`synced_at`) — для следующего запроса изменений.
public struct SyncedRow<Record: SyncedRecord>: Decodable, Sendable {
    public let record: Record
    public let syncedAt: Date

    enum CodingKeys: String, CodingKey {
        case syncedAt = "synced_at"
    }

    public init(from decoder: any Decoder) throws {
        record = try Record(from: decoder)
        syncedAt = try decoder.container(keyedBy: CodingKeys.self).decode(Date.self, forKey: .syncedAt)
    }
}

extension BackendClient {
    /// Отправляет свои правки (новые, изменённые, удалённые) и возвращает принятые. Сервер
    /// оставляет более свежую правку. Запись, которую сервер отклонил (лимит, неверные данные),
    /// не мешает остальным; нет сети — ошибка.
    public func push<Record: SyncedRecord>(_ records: [Record]) async throws -> [Record] {
        var accepted: [Record] = []
        for start in stride(from: 0, to: records.count, by: 200) {
            let chunk = Array(records[start..<min(start + 200, records.count)])
            do {
                try await upsert(chunk)
                accepted += chunk
            } catch is PostgrestError {
                for record in chunk {
                    do {
                        try await upsert([record])
                        accepted.append(record)
                    } catch is PostgrestError {
                        continue
                    }
                }
            }
        }
        return accepted
    }

    private func upsert<Record: SyncedRecord>(_ records: [Record]) async throws {
        try await supabase
            .from(Record.recordKind)
            .upsert(records, onConflict: "id", returning: .minimal)
            .execute()
    }

    /// Свои записи, которые сервер принял после `since` (все — если `nil`), по возрастанию `synced_at`.
    /// Незнакомые записи (из новой версии) пропускаются.
    public func pull<Record: SyncedRecord>(_ type: Record.Type, since: Date?) async throws -> [SyncedRow<Record>] {
        let pageSize = 500
        var latest: [UUID: SyncedRow<Record>] = [:]
        var cursor = since
        // Следующие страницы — «не раньше» последней: у записей одной отправки одинаковое время.
        var inclusive = false
        while true {
            var query = supabase.from(Record.recordKind).select()
            if let cursor {
                let value = Self.timestamp(cursor)
                query = inclusive ? query.gte("synced_at", value: value) : query.gt("synced_at", value: value)
            }
            let page: [Lenient<SyncedRow<Record>>] = try await query
                .order("synced_at")
                .limit(pageSize)
                .execute()
                .value
            let decoded = page.compactMap(\.value)
            for row in decoded where (latest[row.record.id]?.syncedAt ?? .distantPast) <= row.syncedAt {
                latest[row.record.id] = row
            }
            guard page.count == pageSize, let last = decoded.last?.syncedAt, last != cursor else { break }
            cursor = last
            inclusive = true
        }
        return latest.values.sorted { $0.syncedAt < $1.syncedAt }
    }

    /// Шаблоны чеклистов редакции (для всех, в том числе гостей).
    public func checklistTemplates() async throws -> [ChecklistTemplate] {
        let rows: [Lenient<ChecklistTemplate>] = try await supabase
            .from("checklist_templates")
            .select("id,sort_order,title_ru,title_kk,title_en,note_ru,note_kk,note_en,items")
            .order("sort_order")
            .execute()
            .value
        return rows.compactMap(\.value)
    }

    /// Время для фильтра PostgREST в UTC с микросекундами (как хранит Postgres), с округлением
    /// вниз — чтобы не пропустить запись.
    static func timestamp(_ date: Date) -> String {
        let seconds = date.timeIntervalSince1970
        let whole = seconds.rounded(.down)
        let micros = min(Int(((seconds - whole) * 1_000_000).rounded(.down)), 999_999)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: whole)) + String(format: ".%06dZ", micros)
    }
}
