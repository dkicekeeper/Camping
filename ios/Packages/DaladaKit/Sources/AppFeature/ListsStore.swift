import Backend
import DaladaCore
import Foundation
import Observation
import Persistence

/// Экипировка и чеклисты. Хранятся на телефоне и работают без сети и без аккаунта; после входа
/// синхронизируются с сервером (побеждает последняя правка). Правка сразу видна и сохраняется,
/// на сервер уходит через пару секунд, при возврате в приложение или когда появится сеть.
/// Передаётся через `.environment`.
@MainActor
@Observable
final class ListsStore {
    /// Предметы экипировки: по категориям, внутри — по названию.
    private(set) var gear: [GearItem] = []
    /// Чеклисты и сборы (без удалённых).
    private(set) var checklists: [Checklist] = []
    /// Шаблоны редакции.
    private(set) var templates: [ChecklistTemplate] = []
    /// Есть правки, которые ещё не на сервере (только после входа).
    private(set) var hasUnsyncedChanges = false

    private let backend: BackendClient?
    private let store: OwnRecordStore
    private let cache: CacheStore?
    private var userID: UUID?
    private var syncTask: Task<Void, Never>?
    private var isSyncing = false
    private var syncsAgain = false
    private var templatesRefreshedAt: Date?
    private var lastStamp = Date.distantPast
    /// Записи, чья правка ещё пишется на диск: при перечитывании берём их из памяти.
    private var pendingWrites: [UUID: Int] = [:]

    init(backend: BackendClient?, database: LocalDatabase, cache: CacheStore? = nil) {
        self.backend = backend
        self.store = database.ownRecords
        self.cache = cache
    }

    private var account: String { OwnRecordStore.account(for: userID) }

    // MARK: Аккаунт

    /// Запуск приложения, вход или выход. После входа списки гостя переходят в аккаунт.
    func switchUser(from previous: UUID?, to current: UUID?) async {
        if let previous, previous != current, backend?.isSignedIn != true {
            // Вышел из аккаунта: его списки на телефоне не остаются (кроме неотправленных правок).
            try? await store.removeSynced(account: OwnRecordStore.account(for: previous))
        }
        userID = current
        if current != nil {
            try? await store.adopt(from: OwnRecordStore.guestAccount, into: account)
        }
        await reload()
        await sync()
    }

    // MARK: Чтение

    var packingLists: [Checklist] {
        checklists.filter { $0.kind == .packing }.sorted(by: Self.packingOrder)
    }

    var ownLists: [Checklist] {
        checklists.filter { $0.kind == .list }
    }

    /// Ближайшие сборы: поездка сегодня или позже (или без даты), ещё не собрано.
    var upcomingPacking: Checklist? {
        let today = CalendarDay(Date())
        return packingLists.first { packing in
            !packing.isComplete && (packing.tripDate.map { $0 >= today } ?? true)
        }
    }

    func checklist(_ id: UUID) -> Checklist? {
        checklists.first { $0.id == id }
    }

    func gearItem(_ id: UUID) -> GearItem? {
        gear.first { $0.id == id }
    }

    /// Сборы с датой — по дате поездки, без даты — после, по времени правки.
    private static func packingOrder(_ a: Checklist, _ b: Checklist) -> Bool {
        switch (a.tripDate, b.tripDate) {
        case let (x?, y?): x == y ? a.updatedAt > b.updatedAt : x < y
        case (.some, .none): true
        case (.none, .some): false
        case (.none, .none): a.updatedAt > b.updatedAt
        }
    }

    private static func gearOrder(_ a: GearItem, _ b: GearItem) -> Bool {
        let ai = GearCategory.allCases.firstIndex(of: a.category) ?? 0
        let bi = GearCategory.allCases.firstIndex(of: b.category) ?? 0
        if ai != bi { return ai < bi }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    // MARK: Экипировка

    func save(_ item: GearItem) {
        var item = item
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.brand = item.brand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.updatedAt = nextStamp()
        gear.removeAll { $0.id == item.id }
        if !item.isDeleted {
            gear.append(item)
            gear.sort(by: Self.gearOrder)
        }
        persist(item)
    }

    func delete(_ item: GearItem) {
        var item = item
        item.deletedAt = SyncClock.now()
        save(item)
    }

    /// Быстрое добавление популярных предметов на языке интерфейса (уже добавленные не повторяются).
    func addPopular(_ items: [ChecklistTemplate.Item], language: String) {
        let existing = Set(gear.map { $0.name.lowercased() })
        for item in items {
            let name = item.title.text(for: language)
            guard !existing.contains(name.lowercased()) else { continue }
            save(GearItem(name: name, category: item.category))
        }
    }

    // MARK: Чеклисты

    func save(_ checklist: Checklist) {
        var checklist = checklist
        checklist.title = checklist.title.trimmingCharacters(in: .whitespacesAndNewlines)
        checklist.updatedAt = nextStamp()
        checklists.removeAll { $0.id == checklist.id }
        if !checklist.isDeleted {
            checklists.insert(checklist, at: 0)
        }
        persist(checklist)
        Task { await PackingReminders.update(checklists) }
    }

    func delete(_ checklist: Checklist) {
        var checklist = checklist
        checklist.deletedAt = SyncClock.now()
        save(checklist)
    }

    /// Изменить чеклист по id (отметка, новый пункт и т. п.).
    func update(_ id: UUID, _ change: (inout Checklist) -> Void) {
        guard var checklist = checklist(id) else { return }
        change(&checklist)
        save(checklist)
    }

    /// Сборы по шаблону — сразу в «Мои сборы».
    @discardableResult
    func startPacking(
        from template: ChecklistTemplate,
        title: String,
        tripDate: CalendarDay?,
        remindMinutes: Int?,
        language: String
    ) -> Checklist {
        var packing = template.makeChecklist(kind: .packing, language: language, tripDate: tripDate)
        packing.title = title
        packing.remindMinutes = tripDate == nil ? nil : remindMinutes
        save(packing)
        return packing
    }

    /// Сборы по своему чеклисту.
    @discardableResult
    func startPacking(from list: Checklist, title: String, tripDate: CalendarDay?, remindMinutes: Int?) -> Checklist {
        var packing = list.packingCopy(title: title, tripDate: tripDate)
        packing.remindMinutes = tripDate == nil ? nil : remindMinutes
        save(packing)
        return packing
    }

    /// Свой чеклист из шаблона (чтобы поменять под себя).
    @discardableResult
    func copyToMyLists(_ template: ChecklistTemplate, language: String) -> Checklist {
        let list = template.makeChecklist(kind: .list, language: language)
        save(list)
        return list
    }

    // MARK: Шаблоны

    /// Сохранённая копия шаблонов, потом свежая с сервера — не чаще раза в час.
    func loadTemplates() async {
        if templates.isEmpty, let cached = try? await cache?.load([ChecklistTemplate].self, for: .checklistTemplates) {
            templates = cached
        }
        guard let backend else { return }
        if let templatesRefreshedAt, Date().timeIntervalSince(templatesRefreshedAt) < 3600 { return }
        if let loaded = try? await backend.checklistTemplates(), !loaded.isEmpty {
            templates = loaded
            templatesRefreshedAt = Date()
            try? await cache?.save(loaded, for: .checklistTemplates)
        }
    }

    // MARK: Хранение и синхронизация

    /// Время правки: не раньше предыдущей своей правки, чтобы порядок правок сохранялся.
    private func nextStamp() -> Date {
        let now = SyncClock.now()
        lastStamp = max(now, lastStamp.addingTimeInterval(0.001))
        return lastStamp
    }

    private func persist<Record: SyncedRecord>(_ record: Record) {
        let account = self.account
        let store = self.store
        pendingWrites[record.id, default: 0] += 1
        Task {
            try? await store.save(record, account: account)
            let left = (pendingWrites[record.id] ?? 1) - 1
            pendingWrites[record.id] = left > 0 ? left : nil
            if userID != nil {
                hasUnsyncedChanges = true
            }
            scheduleSync()
        }
    }

    /// Перечитать списки с диска (после синхронизации или смены аккаунта).
    func reload() async {
        let account = self.account
        let loadedGear = (try? await store.all(GearItem.self, account: account)) ?? []
        let loadedLists = (try? await store.all(Checklist.self, account: account)) ?? []
        let dirtyGear = (try? await store.dirty(GearItem.self, account: account)) ?? []
        let dirtyLists = (try? await store.dirty(Checklist.self, account: account)) ?? []
        guard account == self.account else { return }
        gear = merged(loadedGear, inMemory: gear).sorted(by: Self.gearOrder)
        checklists = merged(loadedLists, inMemory: checklists).sorted { $0.updatedAt > $1.updatedAt }
        hasUnsyncedChanges = userID != nil && !(dirtyGear.isEmpty && dirtyLists.isEmpty)
        await PackingReminders.update(checklists)
    }

    /// С диска, кроме записей, чья правка ещё пишется: их версия — в памяти.
    private func merged<Record: SyncedRecord>(_ loaded: [Record], inMemory: [Record]) -> [Record] {
        loaded.filter { pendingWrites[$0.id] == nil } + inMemory.filter { pendingWrites[$0.id] != nil }
    }

    /// Отправить через пару секунд (правки подряд уходят одним запросом).
    func scheduleSync(after delay: Duration = .seconds(2)) {
        guard userID != nil, backend != nil else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    /// Отправить свои правки и забрать правки с других устройств. Без сети — в следующий раз.
    func sync() async {
        guard let backend, let userID, backend.currentUserID == userID else { return }
        if isSyncing {
            syncsAgain = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        let account = self.account
        repeat {
            syncsAgain = false
            do {
                try await sync(GearItem.self, backend: backend, account: account)
                try await sync(Checklist.self, backend: backend, account: account)
            } catch {
                break
            }
        } while syncsAgain && account == self.account
        if account == self.account {
            await reload()
        }
    }

    private func sync<Record: SyncedRecord>(_ type: Record.Type, backend: BackendClient, account: String) async throws {
        let dirty = try await store.dirty(Record.self, account: account)
        if !dirty.isEmpty {
            let accepted = try await backend.push(dirty)
            try await store.markSynced(accepted, account: account)
        }
        // С запасом в минуту: запись, принятая чуть раньше последней полученной, не потеряется.
        let cursor = try await store.cursor(kind: Record.recordKind, account: account)
        let rows = try await backend.pull(Record.self, since: cursor?.addingTimeInterval(-60))
        guard let last = rows.last?.syncedAt else { return }
        try await store.applyRemote(rows.map(\.record), account: account)
        try await store.setCursor(max(last, cursor ?? last), kind: Record.recordKind, account: account)
    }
}

extension String {
    /// `nil` вместо пустой строки.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
