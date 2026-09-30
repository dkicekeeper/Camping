import DaladaCore
import Foundation
@testable import Persistence
import Testing

@Suite("Свои списки на телефоне")
struct OwnRecordStoreTests {
    let account = OwnRecordStore.account(for: UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let base = Date(timeIntervalSince1970: 1_790_000_000.123)

    private func gear(_ name: String, id: UUID = UUID(), at offset: TimeInterval = 0) -> GearItem {
        GearItem(id: id, name: name, category: .rods, weightGrams: 300, updatedAt: base.addingTimeInterval(offset))
    }

    @Test func savesAndListsPerAccount() async throws {
        let store = try LocalDatabase.inMemory().ownRecords
        try await store.save(gear("Фидер"), account: account)
        try await store.save(gear("Спиннинг"), account: OwnRecordStore.guestAccount)

        #expect(try await store.all(GearItem.self, account: account).map(\.name) == ["Фидер"])
        #expect(try await store.all(GearItem.self, account: OwnRecordStore.guestAccount).map(\.name) == ["Спиннинг"])
        #expect(try await store.all(Checklist.self, account: account).isEmpty, "виды записей не смешиваются")
        #expect(account == "11111111-1111-1111-1111-111111111111")
    }

    @Test func olderLocalWriteDoesNotOverwriteNewer() async throws {
        let store = try LocalDatabase.inMemory().ownRecords
        let id = UUID()
        try await store.save(gear("Вторая правка", id: id, at: 2), account: account)
        try await store.save(gear("Первая правка", id: id, at: 1), account: account)
        #expect(try await store.all(GearItem.self, account: account).map(\.name) == ["Вторая правка"])
    }

    @Test func deletedAreHiddenButStillSent() async throws {
        let store = try LocalDatabase.inMemory().ownRecords
        var item = gear("Палатка")
        try await store.save(item, account: account)
        item.deletedAt = base
        item.updatedAt = base.addingTimeInterval(1)
        try await store.save(item, account: account)

        #expect(try await store.all(GearItem.self, account: account).isEmpty)
        #expect(try await store.all(GearItem.self, account: account, includeDeleted: true).count == 1)
        #expect(try await store.dirty(GearItem.self, account: account).first?.isDeleted == true)
    }

    @Test func markSyncedKeepsNewerEdit() async throws {
        let store = try LocalDatabase.inMemory().ownRecords
        var item = gear("Катушка")
        try await store.save(item, account: account)
        let sent = try await store.dirty(GearItem.self, account: account)

        // Пока шла отправка, предмет поправили ещё раз.
        item.name = "Катушка 3000"
        item.updatedAt = base.addingTimeInterval(5)
        try await store.save(item, account: account)
        try await store.markSynced(sent, account: account)
        #expect(try await store.dirty(GearItem.self, account: account).map(\.name) == ["Катушка 3000"])

        try await store.markSynced([item], account: account)
        #expect(try await store.dirty(GearItem.self, account: account).isEmpty)
    }

    @Test func remoteChangesMergeLastEditWins() async throws {
        let store = try LocalDatabase.inMemory().ownRecords
        let id = UUID()
        try await store.save(gear("Своя правка", id: id, at: 10), account: account)

        // С сервера пришла более старая версия — своя неотправленная правка остаётся.
        #expect(try await store.applyRemote([gear("Старая с сервера", id: id, at: 5)], account: account) == 0)
        #expect(try await store.all(GearItem.self, account: account).map(\.name) == ["Своя правка"])

        // Более новая с другого устройства — побеждает и больше не ждёт отправки.
        let newer = gear("С планшета", id: id, at: 20)
        let other = gear("Новый с планшета", at: 3)
        #expect(try await store.applyRemote([newer, other], account: account) == 2)
        #expect(Set(try await store.all(GearItem.self, account: account).map(\.name)) == ["С планшета", "Новый с планшета"])
        #expect(try await store.dirty(GearItem.self, account: account).isEmpty)

        // Та же версия ещё раз (перекрытие окна синхронизации) — ничего не меняет.
        #expect(try await store.applyRemote([newer], account: account) == 0)
    }

    @Test func cursorIsPerAccountAndKind() async throws {
        let store = try LocalDatabase.inMemory().ownRecords
        #expect(try await store.cursor(kind: GearItem.recordKind, account: account) == nil)
        try await store.setCursor(base, kind: GearItem.recordKind, account: account)
        #expect(try await store.cursor(kind: GearItem.recordKind, account: account) == base)
        #expect(try await store.cursor(kind: Checklist.recordKind, account: account) == nil)
    }

    @Test func guestListsMoveIntoAccountAfterSignIn() async throws {
        let store = try LocalDatabase.inMemory().ownRecords
        try await store.save(Checklist(title: "Мои сборы", updatedAt: base), account: OwnRecordStore.guestAccount)
        try await store.applyRemote([gear("С сервера")], account: account)

        #expect(try await store.adopt(from: OwnRecordStore.guestAccount, into: account) == 1)
        #expect(try await store.all(Checklist.self, account: OwnRecordStore.guestAccount).isEmpty)
        #expect(try await store.dirty(Checklist.self, account: account).map(\.title) == ["Мои сборы"])
    }

    @Test func signOutKeepsOnlyUnsentEdits() async throws {
        let store = try LocalDatabase.inMemory().ownRecords
        try await store.applyRemote([gear("Отправленный")], account: account)
        try await store.save(gear("Неотправленный"), account: account)
        try await store.setCursor(base, kind: GearItem.recordKind, account: account)

        try await store.removeSynced(account: account)
        #expect(try await store.all(GearItem.self, account: account).map(\.name) == ["Неотправленный"])
        #expect(try await store.cursor(kind: GearItem.recordKind, account: account) == nil)
    }

    @Test func deletedAccountLosesEverything() async throws {
        let store = try LocalDatabase.inMemory().ownRecords
        try await store.save(gear("Неотправленный"), account: account)
        try await store.applyRemote([gear("Отправленный")], account: account)
        try await store.save(gear("Гостевой"), account: OwnRecordStore.guestAccount)
        try await store.removeAll(account: account)
        #expect(try await store.all(GearItem.self, account: account, includeDeleted: true).isEmpty)
        #expect(try await store.all(GearItem.self, account: OwnRecordStore.guestAccount).count == 1)
    }

    @Test func checklistRoundTripsWithItems() async throws {
        let store = try LocalDatabase.inMemory().ownRecords
        let checklist = Checklist(
            kind: .packing,
            title: "Капшагай",
            templateID: "fishing_day",
            tripDate: CalendarDay(year: 2026, month: 10, day: 3),
            remindMinutes: 20 * 60,
            items: [ChecklistItem(id: "rods", title: "Удилища", category: .rods, isChecked: true)],
            updatedAt: base
        )
        try await store.save(checklist, account: account)
        #expect(try await store.all(Checklist.self, account: account) == [checklist])
    }
}
