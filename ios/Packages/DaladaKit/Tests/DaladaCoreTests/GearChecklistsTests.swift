import Foundation
import Testing
@testable import DaladaCore

@Suite("Экипировка и чеклисты")
struct GearChecklistsTests {
    private var template: ChecklistTemplate {
        ChecklistTemplate(
            id: "fishing_day",
            title: LocalizedText(ru: "Рыбалка на день", kk: "Бір күндік балық аулау", en: "Day fishing"),
            items: [
                .init(id: "rods", category: .rods, title: LocalizedText(ru: "Удилища", kk: "Қармақсаптар", en: "Fishing rods")),
                .init(id: "water", category: .kitchen, title: LocalizedText(ru: "Вода", kk: "Су", en: "")),
                .init(id: "reels", category: .reels, title: LocalizedText(ru: "Катушки", kk: "Катушкалар", en: "Reels")),
            ]
        )
    }

    @Test func lastEditWins() {
        let old = Date(timeIntervalSince1970: 100)
        let new = Date(timeIntervalSince1970: 200)
        #expect(SyncMerge.keepsLocal(localUpdatedAt: new, localIsDirty: true, remoteUpdatedAt: old))
        #expect(!SyncMerge.keepsLocal(localUpdatedAt: old, localIsDirty: true, remoteUpdatedAt: new))
        #expect(!SyncMerge.keepsLocal(localUpdatedAt: new, localIsDirty: false, remoteUpdatedAt: old), "отправленное — берём с сервера")
        #expect(!SyncMerge.keepsLocal(localUpdatedAt: new, localIsDirty: true, remoteUpdatedAt: new), "та же версия уже на сервере")
        #expect(!SyncMerge.keepsLocal(localUpdatedAt: new, localIsDirty: true, remoteUpdatedAt: new.addingTimeInterval(-0.001)),
                "сервер округлил время до миллисекунды — та же версия")
    }

    @Test func syncClockHasMilliseconds() {
        let now = SyncClock.now().timeIntervalSince1970 * 1000
        #expect(abs(now - now.rounded()) < 0.001)
    }

    @Test func packingFromTemplate() {
        let day = CalendarDay(year: 2026, month: 10, day: 3)
        let packing = template.makeChecklist(kind: .packing, language: "en", tripDate: day)
        #expect(packing.kind == .packing)
        #expect(packing.title == "Day fishing")
        #expect(packing.templateID == "fishing_day")
        #expect(packing.tripDate == day)
        #expect(packing.remindMinutes == Checklist.defaultRemindMinutes)
        #expect(packing.items.map(\.title) == ["Fishing rods", "Вода", "Reels"], "нет перевода — русский")
        #expect(packing.items.allSatisfy { !$0.isChecked })

        let list = template.makeChecklist(kind: .list, language: "kk", tripDate: day)
        #expect(list.tripDate == nil && list.remindMinutes == nil, "у заготовки нет дня поездки")
        #expect(list.title == "Бір күндік балық аулау")
    }

    @Test func progressSectionsAndReset() {
        var checklist = template.makeChecklist(kind: .packing, language: "ru")
        checklist.append(ChecklistItem(id: "x", title: "  Сачок  "))
        let addedEmpty = checklist.append(ChecklistItem(id: "y", title: "   "))
        let addedRepeat = checklist.append(ChecklistItem(id: "x", title: "Повтор"))
        #expect(!addedEmpty, "пустой пункт не добавляется")
        #expect(!addedRepeat, "повтор id не добавляется")
        #expect(checklist.items.last?.title == "Сачок")

        checklist.toggle(itemID: "rods")
        checklist.toggle(itemID: "water")
        #expect(checklist.checkedCount == 2)
        #expect(checklist.progress == 0.5)
        #expect(!checklist.isComplete)
        #expect(checklist.sections.map(\.category) == [.rods, .reels, .kitchen, .other], "по порядку категорий, без категории — в «Прочее»")

        let copy = checklist.packingCopy(title: "Ещё раз", tripDate: nil)
        #expect(copy.id != checklist.id)
        #expect(copy.checkedCount == 0 && copy.items.count == 4)
        #expect(copy.remindMinutes == nil)

        checklist.resetChecks()
        #expect(checklist.checkedCount == 0)
    }

    @Test func reminderIsEveningBefore() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Almaty"))
        var packing = template.makeChecklist(kind: .packing, language: "ru", tripDate: CalendarDay(year: 2026, month: 11, day: 1))
        let reminder = try #require(packing.reminderDate(calendar: calendar))
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder)
        #expect(parts == DateComponents(year: 2026, month: 10, day: 31, hour: 20, minute: 0))

        packing.remindMinutes = nil
        #expect(packing.reminderDate(calendar: calendar) == nil)
        #expect(template.makeChecklist(kind: .list, language: "ru").reminderDate(calendar: calendar) == nil)
    }

    @Test func gearSummaryByCategory() {
        let items = [
            GearItem(name: "Фидер", category: .rods, weightGrams: 300, quantity: 2),
            GearItem(name: "Спиннинг", category: .rods, weightGrams: 150),
            GearItem(name: "Палатка", category: .camp, weightGrams: nil),
            GearItem(name: "Старая катушка", category: .reels, weightGrams: 250, deletedAt: Date()),
        ]
        let summary = GearCategorySummary.make(items)
        #expect(summary.map(\.category) == [.rods, .camp])
        #expect(summary[0].count == 3 && summary[0].weightGrams == 750 && !summary[0].hasUnknownWeight)
        #expect(summary[1].hasUnknownWeight)
        #expect(!GearItem(name: " ", quantity: 1).isValid)
        #expect(!GearItem(name: "Грузила", quantity: 0).isValid)
    }

    @Test func popularItemsHaveNoDuplicates() {
        let other = ChecklistTemplate(
            id: "paid_pond",
            title: LocalizedText(ru: "Платник", kk: "", en: ""),
            items: [
                .init(id: "rods", category: .rods, title: LocalizedText(ru: "Удилища", kk: "", en: "")),
                .init(id: "cash", category: .documents, title: LocalizedText(ru: "Наличные", kk: "", en: "")),
            ]
        )
        #expect(ChecklistTemplate.popularItems([template, other]).map(\.id) == ["rods", "water", "reels", "cash"])
    }

    @Test func encodesNullsForServer() throws {
        let item = GearItem(name: "Нож", category: .camp, updatedAt: Date(timeIntervalSince1970: 0))
        let json = try #require(String(data: JSONEncoder().encode(item), encoding: .utf8))
        #expect(json.contains("\"brand\":null"), "пустое поле стирает прежнее значение на сервере")
        #expect(json.contains("\"deleted_at\":null"))

        let item2 = ChecklistItem(id: "a", title: "Нож", gearID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001"))
        let itemJSON = try #require(String(data: JSONEncoder().encode(item2), encoding: .utf8))
        #expect(itemJSON.contains("aaaaaaaa-0000-0000-0000-000000000001"))
    }

    @Test func decodesTolerantly() throws {
        let json = """
        {"id": "cccccccc-0000-0000-0000-000000000001", "kind": "trip_plan", "title": "Сборы",
         "template_id": null, "trip_date": "2026-10-03", "remind_minutes": 1200,
         "items": [{"id": "a", "title": "Нож", "category": "weapons", "checked": true},
                   {"id": "a", "title": "Повтор"},
                   {"title": "Без id"},
                   {"id": "b", "title": "Вода", "gear_id": "not-a-uuid"}],
         "updated_at": 0, "deleted_at": null}
        """
        let checklist = try JSONDecoder().decode(Checklist.self, from: Data(json.utf8))
        #expect(checklist.kind == .list, "незнакомый вид — заготовка")
        #expect(checklist.items.map(\.id) == ["a", "b"])
        #expect(checklist.items[0].category == .other && checklist.items[0].isChecked)
        #expect(checklist.items[1].gearID == nil)
        #expect(checklist.tripDate == CalendarDay(year: 2026, month: 10, day: 3))
    }
}
