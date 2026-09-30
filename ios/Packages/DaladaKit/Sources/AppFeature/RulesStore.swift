import Backend
import DaladaCore
import Foundation
import MapEngine
import Observation
import Persistence

/// Правила и запреты в памяти: сначала сохранённая копия (работает без сети), потом свежая с
/// сервера — не чаще раза в час. Передаётся через `.environment`.
@MainActor
@Observable
final class RulesStore {
    private(set) var pack: RulesPack?
    private let backend: BackendClient?
    private let cache: CacheStore?
    private var isLoading = false
    private var refreshedAt: Date?

    init(backend: BackendClient?, cache: CacheStore? = nil) {
        self.backend = backend
        self.cache = cache
    }

    func loadIfNeeded() async {
        if pack == nil, let cached = try? await cache?.load(RulesPack.self, for: .rules), !cached.isEmpty {
            pack = cached
        }
        guard let backend, !isLoading else { return }
        if let refreshedAt, Date().timeIntervalSince(refreshedAt) < 3600 { return }
        isLoading = true
        defer { isLoading = false }
        if let loaded = try? await backend.rulesPack(), !loaded.isEmpty {
            pack = loaded
            refreshedAt = Date()
            try? await cache?.save(loaded, for: .rules)
        }
    }

    /// Сегодня по времени Алматы: сроки в приказах — календарные дни.
    static var today: CalendarDay {
        CalendarDay(Date(), calendar: almatyCalendar)
    }

    static let almatyCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty") ?? .current
        return calendar
    }()

    /// Язык текстов правил: язык интерфейса, иначе русский.
    static var language: String {
        SpeciesStore.languageCode ?? "ru"
    }

    /// Зоны для карты с цветом по состоянию запрета на сегодня.
    func mapAreas(on day: CalendarDay = RulesStore.today) -> [MapRuleArea] {
        guard let pack else { return [] }
        return pack.zones.compactMap { zone in
            guard !zone.polygons.isEmpty else { return nil }
            let state: MapRuleArea.State = switch pack.banState(ofZone: zone.id, on: day) {
            case .active: .active
            case .soon: .soon
            case .none: .none
            }
            return MapRuleArea(id: zone.id, polygons: zone.polygons.map(\.rings), state: state)
        }
    }
}
