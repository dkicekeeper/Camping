import Foundation

// MARK: - Синхронизация своих списков

/// Своя запись, которая хранится на телефоне и синхронизируется с сервером: побеждает последняя
/// правка (`updatedAt` — время правки на телефоне), удаление — пометка `deletedAt`.
public protocol SyncedRecord: Codable, Identifiable, Sendable where ID == UUID {
    /// Вид записи в локальной базе и имя таблицы на сервере.
    static var recordKind: String { get }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
}

extension SyncedRecord {
    public var isDeleted: Bool { deletedAt != nil }
}

public enum SyncClock {
    /// Сейчас с точностью до миллисекунды — так время правки одинаково на телефоне и на сервере.
    public static func now() -> Date {
        Date(timeIntervalSince1970: (Date().timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}

/// Что делать с записью, пришедшей с сервера.
public enum SyncMerge {
    /// Сервер хранит время правки с точностью до миллисекунды: разница меньше — та же версия.
    public static let tolerance: TimeInterval = 0.002

    /// Своя неотправленная правка новее серверной — оставляем свою (она уйдёт при отправке).
    /// Иначе берём серверную.
    public static func keepsLocal(localUpdatedAt: Date, localIsDirty: Bool, remoteUpdatedAt: Date) -> Bool {
        localIsDirty && localUpdatedAt.timeIntervalSince(remoteUpdatedAt) > tolerance
    }
}

// MARK: - Экипировка

/// Категория предмета экипировки и пункта чеклиста.
public enum GearCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case rods
    case reels
    case tackle
    case clothing
    case camp
    case kitchen
    case power
    case navigation
    case firstAid = "first_aid"
    case boat
    case documents
    case other

    public var id: String { rawValue }

    /// Ключ названия в `Localizable.xcstrings`.
    public var titleKey: String { "gear.category.\(rawValue)" }

    public var systemImage: String {
        switch self {
        case .rods: "figure.fishing"
        case .reels: "gearshape.2"
        case .tackle: "fish"
        case .clothing: "tshirt"
        case .camp: "tent"
        case .kitchen: "fork.knife"
        case .power: "flashlight.on.fill"
        case .navigation: "location.north.circle"
        case .firstAid: "cross.case"
        case .boat: "sailboat"
        case .documents: "doc.text"
        case .other: "shippingbox"
        }
    }

    /// Незнакомая категория (из новой версии сервера) — «Прочее».
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GearCategory(rawValue: raw) ?? .other
    }
}

/// Состояние предмета.
public enum GearStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case ok
    case repair
    case buy

    public var id: String { rawValue }
    public var titleKey: String { "gear.status.\(rawValue)" }

    public var systemImage: String {
        switch self {
        case .ok: "checkmark.circle"
        case .repair: "wrench.and.screwdriver"
        case .buy: "cart"
        }
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GearStatus(rawValue: raw) ?? .ok
    }
}

/// Предмет экипировки — строка `gear_items`.
public struct GearItem: SyncedRecord, Hashable {
    public static let recordKind = "gear_items"

    public let id: UUID
    public var name: String
    public var category: GearCategory
    /// Бренд и модель.
    public var brand: String?
    /// Вес одной штуки, г.
    public var weightGrams: Int?
    public var quantity: Int
    public var status: GearStatus
    public var note: String?
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        category: GearCategory = .other,
        brand: String? = nil,
        weightGrams: Int? = nil,
        quantity: Int = 1,
        status: GearStatus = .ok,
        note: String? = nil,
        updatedAt: Date = SyncClock.now(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.brand = brand
        self.weightGrams = weightGrams
        self.quantity = quantity
        self.status = status
        self.note = note
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Можно сохранить: есть название, количество от 1 до 999, вес в разумных пределах.
    public var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...100).contains(trimmed.count)
            && (1...999).contains(quantity)
            && (weightGrams.map { (0...1_000_000).contains($0) } ?? true)
            && (brand?.count ?? 0) <= 100
            && (note?.count ?? 0) <= 1000
    }

    /// Общий вес всех штук, г.
    public var totalWeightGrams: Int? {
        weightGrams.map { $0 * quantity }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, category, brand, quantity, status, note
        case weightGrams = "weight_grams"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = (try? c.decode(GearCategory.self, forKey: .category)) ?? .other
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        weightGrams = try c.decodeIfPresent(Int.self, forKey: .weightGrams)
        quantity = try c.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        status = (try? c.decode(GearStatus.self, forKey: .status)) ?? .ok
        note = try c.decodeIfPresent(String.self, forKey: .note)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    /// Пустые поля пишутся как `null`: при отправке на сервер они должны стирать прежние значения.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .category)
        try c.encode(brand, forKey: .brand)
        try c.encode(weightGrams, forKey: .weightGrams)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(status, forKey: .status)
        try c.encode(note, forKey: .note)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

/// Сводка экипировки по категории: сколько штук и сколько весят (если вес указан).
public struct GearCategorySummary: Identifiable, Hashable, Sendable {
    public let category: GearCategory
    public let count: Int
    public let weightGrams: Int
    /// У части предметов вес не указан — сумма неполная.
    public let hasUnknownWeight: Bool

    public var id: GearCategory { category }

    /// По категориям в порядке `GearCategory.allCases`; пустые пропускаются. Удалённые не считаются.
    public static func make(_ items: [GearItem]) -> [GearCategorySummary] {
        let live = items.filter { !$0.isDeleted }
        return GearCategory.allCases.compactMap { category in
            let inCategory = live.filter { $0.category == category }
            guard !inCategory.isEmpty else { return nil }
            return GearCategorySummary(
                category: category,
                count: inCategory.reduce(0) { $0 + $1.quantity },
                weightGrams: inCategory.reduce(0) { $0 + ($1.totalWeightGrams ?? 0) },
                hasUnknownWeight: inCategory.contains { $0.weightGrams == nil }
            )
        }
    }
}

// MARK: - Чеклисты

/// `list` — свой чеклист-заготовка; `packing` — сборы на конкретную поездку (копия с отметками).
public enum ChecklistKind: String, Codable, Sendable {
    case list
    case packing

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChecklistKind(rawValue: raw) ?? .list
    }
}

/// Пункт чеклиста.
public struct ChecklistItem: Codable, Identifiable, Hashable, Sendable {
    /// Id пункта шаблона («rods») или случайный — для своих пунктов.
    public let id: String
    public var title: String
    public var category: GearCategory?
    /// Предмет из «Моей экипировки», из которого добавлен пункт.
    public var gearID: UUID?
    public var isChecked: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        category: GearCategory? = nil,
        gearID: UUID? = nil,
        isChecked: Bool = false
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.gearID = gearID
        self.isChecked = isChecked
    }

    enum CodingKeys: String, CodingKey {
        case id, title, category
        case gearID = "gear_id"
        case isChecked = "checked"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        category = try? c.decodeIfPresent(GearCategory.self, forKey: .category)
        gearID = (try? c.decodeIfPresent(String.self, forKey: .gearID)).flatMap(UUID.init(uuidString:))
        isChecked = (try? c.decodeIfPresent(Bool.self, forKey: .isChecked)) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(gearID?.uuidString.lowercased(), forKey: .gearID)
        try c.encode(isChecked, forKey: .isChecked)
    }
}

/// Пункты одной категории — для показа чеклиста по группам.
public struct ChecklistSection: Identifiable, Hashable, Sendable {
    public let category: GearCategory
    public let items: [ChecklistItem]

    public var id: GearCategory { category }
}

/// Чеклист или сборы на поездку — строка `checklists`.
public struct Checklist: SyncedRecord, Hashable {
    public static let recordKind = "checklists"
    /// Не больше пунктов в чеклисте (как на сервере).
    public static let itemLimit = 300
    /// Напоминание по умолчанию — накануне в 20:00.
    public static let defaultRemindMinutes = 20 * 60

    public let id: UUID
    public var kind: ChecklistKind
    public var title: String
    public var templateID: String?
    /// Сборы: день поездки.
    public var tripDate: CalendarDay?
    /// Напоминание накануне поездки в это время (минуты от полуночи); `nil` — без напоминания.
    public var remindMinutes: Int?
    public var items: [ChecklistItem]
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: ChecklistKind = .list,
        title: String,
        templateID: String? = nil,
        tripDate: CalendarDay? = nil,
        remindMinutes: Int? = nil,
        items: [ChecklistItem] = [],
        updatedAt: Date = SyncClock.now(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.templateID = templateID
        self.tripDate = tripDate
        self.remindMinutes = remindMinutes
        self.items = items
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var isValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...100).contains(trimmed.count) && items.count <= Self.itemLimit
    }

    public var checkedCount: Int { items.filter(\.isChecked).count }

    /// Доля отмеченных пунктов (0…1).
    public var progress: Double {
        items.isEmpty ? 0 : Double(checkedCount) / Double(items.count)
    }

    public var isComplete: Bool { !items.isEmpty && checkedCount == items.count }

    /// Пункты по категориям в порядке `GearCategory.allCases`; без категории — в «Прочее».
    /// Внутри категории — в порядке добавления.
    public var sections: [ChecklistSection] {
        GearCategory.allCases.compactMap { category in
            let inCategory = items.filter { ($0.category ?? .other) == category }
            return inCategory.isEmpty ? nil : ChecklistSection(category: category, items: inCategory)
        }
    }

    /// Отметить или снять отметку.
    public mutating func toggle(itemID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].isChecked.toggle()
    }

    /// «Сбросить»: снять все отметки.
    public mutating func resetChecks() {
        for index in items.indices {
            items[index].isChecked = false
        }
    }

    /// Добавить пункт в конец (пустое название и лишние пункты не добавляются).
    @discardableResult
    public mutating func append(_ item: ChecklistItem) -> Bool {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...200).contains(title.count), items.count < Self.itemLimit,
              !items.contains(where: { $0.id == item.id })
        else { return false }
        var item = item
        item.title = title
        items.append(item)
        return true
    }

    /// Сборы по этому чеклисту: новая копия без отметок.
    public func packingCopy(title: String? = nil, tripDate: CalendarDay?, id: UUID = UUID()) -> Checklist {
        var copy = Checklist(
            id: id,
            kind: .packing,
            title: title ?? self.title,
            templateID: templateID,
            tripDate: tripDate,
            remindMinutes: tripDate == nil ? nil : Self.defaultRemindMinutes,
            items: items
        )
        copy.resetChecks()
        return copy
    }

    /// Когда напомнить о сборах: накануне дня поездки в `remindMinutes` по календарю `calendar`.
    public func reminderDate(calendar: Calendar = .current) -> Date? {
        guard kind == .packing, !isDeleted, let tripDate, let remindMinutes else { return nil }
        let tripDay = tripDate.date(calendar: calendar)
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: tripDay) else { return nil }
        let start = calendar.startOfDay(for: dayBefore)
        return calendar.date(bySettingHour: remindMinutes / 60, minute: remindMinutes % 60, second: 0, of: start)
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, items
        case templateID = "template_id"
        case tripDate = "trip_date"
        case remindMinutes = "remind_minutes"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = (try? c.decode(ChecklistKind.self, forKey: .kind)) ?? .list
        title = try c.decode(String.self, forKey: .title)
        templateID = try c.decodeIfPresent(String.self, forKey: .templateID)
        tripDate = try? c.decodeIfPresent(CalendarDay.self, forKey: .tripDate)
        remindMinutes = try c.decodeIfPresent(Int.self, forKey: .remindMinutes)
        // Пункт, который не разобрался, и повтор id пропускаются — остальные остаются.
        var seen = Set<String>()
        items = (try c.decodeIfPresent([Lenient<ChecklistItem>].self, forKey: .items) ?? [])
            .compactMap(\.value)
            .filter { seen.insert($0.id).inserted }
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encode(templateID, forKey: .templateID)
        try c.encode(tripDate, forKey: .tripDate)
        try c.encode(remindMinutes, forKey: .remindMinutes)
        try c.encode(items, forKey: .items)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

// MARK: - Шаблоны редакции

/// Шаблон чеклиста — строка `checklist_templates` (на трёх языках).
public struct ChecklistTemplate: Codable, Identifiable, Hashable, Sendable {
    public struct Item: Codable, Identifiable, Hashable, Sendable {
        public let id: String
        public let category: GearCategory
        public let title: LocalizedText

        public init(id: String, category: GearCategory, title: LocalizedText) {
            self.id = id
            self.category = category
            self.title = title
        }

        enum CodingKeys: String, CodingKey {
            case id, category
            case titleRU = "title_ru", titleKK = "title_kk", titleEN = "title_en"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            category = (try? c.decode(GearCategory.self, forKey: .category)) ?? .other
            title = LocalizedText(
                ru: try c.decode(String.self, forKey: .titleRU),
                kk: try c.decodeIfPresent(String.self, forKey: .titleKK) ?? "",
                en: try c.decodeIfPresent(String.self, forKey: .titleEN) ?? ""
            )
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(category, forKey: .category)
            try c.encode(title.ru, forKey: .titleRU)
            try c.encode(title.kk, forKey: .titleKK)
            try c.encode(title.en, forKey: .titleEN)
        }
    }

    public let id: String
    public let title: LocalizedText
    public let note: LocalizedText?
    public let items: [Item]
    public let sortOrder: Int

    public init(id: String, title: LocalizedText, note: LocalizedText? = nil, items: [Item], sortOrder: Int = 100) {
        self.id = id
        self.title = title
        self.note = note
        self.items = items
        self.sortOrder = sortOrder
    }

    /// Свой чеклист или сборы по шаблону на языке `language`.
    public func makeChecklist(
        kind: ChecklistKind,
        language: String,
        tripDate: CalendarDay? = nil,
        id: UUID = UUID()
    ) -> Checklist {
        Checklist(
            id: id,
            kind: kind,
            title: title.text(for: language),
            templateID: self.id,
            tripDate: kind == .packing ? tripDate : nil,
            remindMinutes: kind == .packing && tripDate != nil ? Checklist.defaultRemindMinutes : nil,
            items: items.prefix(Checklist.itemLimit).map { item in
                ChecklistItem(id: item.id, title: item.title.text(for: language), category: item.category)
            }
        )
    }

    /// Предметы из всех шаблонов без повторов — для быстрого добавления в экипировку.
    public static func popularItems(_ templates: [ChecklistTemplate]) -> [Item] {
        var seen = Set<String>()
        return templates.flatMap(\.items).filter { seen.insert($0.id).inserted }
    }

    enum CodingKeys: String, CodingKey {
        case id, items
        case titleRU = "title_ru", titleKK = "title_kk", titleEN = "title_en"
        case noteRU = "note_ru", noteKK = "note_kk", noteEN = "note_en"
        case sortOrder = "sort_order"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = LocalizedText(
            ru: try c.decode(String.self, forKey: .titleRU),
            kk: try c.decodeIfPresent(String.self, forKey: .titleKK) ?? "",
            en: try c.decodeIfPresent(String.self, forKey: .titleEN) ?? ""
        )
        if let ru = try c.decodeIfPresent(String.self, forKey: .noteRU) {
            note = LocalizedText(
                ru: ru,
                kk: try c.decodeIfPresent(String.self, forKey: .noteKK) ?? "",
                en: try c.decodeIfPresent(String.self, forKey: .noteEN) ?? ""
            )
        } else {
            note = nil
        }
        items = (try c.decodeIfPresent([Lenient<Item>].self, forKey: .items) ?? []).compactMap(\.value)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 100
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title.ru, forKey: .titleRU)
        try c.encode(title.kk, forKey: .titleKK)
        try c.encode(title.en, forKey: .titleEN)
        try c.encodeIfPresent(note?.ru, forKey: .noteRU)
        try c.encodeIfPresent(note?.kk, forKey: .noteKK)
        try c.encodeIfPresent(note?.en, forKey: .noteEN)
        try c.encode(items, forKey: .items)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}
