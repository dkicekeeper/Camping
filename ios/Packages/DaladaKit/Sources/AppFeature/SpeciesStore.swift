import Backend
import DaladaCore
import Foundation
import Observation
import Persistence

/// Справочник рыб в памяти: загружается один раз, передаётся через `.environment`.
/// Без сети — из кэша, чтобы форма улова работала на водоёме.
@MainActor
@Observable
final class SpeciesStore {
    private(set) var species: [FishSpecies] = []
    private let backend: BackendClient?
    private let cache: CacheStore?
    private var isLoading = false

    init(backend: BackendClient?, cache: CacheStore? = nil) {
        self.backend = backend
        self.cache = cache
    }

    func loadIfNeeded() async {
        guard species.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if let cached = try? await cache?.load([FishSpecies].self, for: .species), !cached.isEmpty {
            species = cached
        }
        guard let backend else { return }
        if let loaded = try? await backend.fishSpecies(), !loaded.isEmpty {
            species = loaded
            try? await cache?.save(loaded, for: .species)
        }
    }

    /// Название вида на языке интерфейса; если справочник ещё не загружен — id.
    func name(for id: String) -> String {
        species.first { $0.id == id }?.name(for: Self.languageCode) ?? id
    }

    /// Язык интерфейса приложения (учитывает язык, выбранный для приложения в Настройках iOS).
    static var languageCode: String? {
        Bundle.main.preferredLocalizations.first
    }
}
