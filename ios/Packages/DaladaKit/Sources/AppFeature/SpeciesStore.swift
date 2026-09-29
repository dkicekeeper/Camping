import Backend
import DaladaCore
import Foundation
import Observation

/// Справочник рыб в памяти: загружается один раз, передаётся через `.environment`.
@MainActor
@Observable
final class SpeciesStore {
    private(set) var species: [FishSpecies] = []
    private let backend: BackendClient?
    private var isLoading = false

    init(backend: BackendClient?) {
        self.backend = backend
    }

    func loadIfNeeded() async {
        guard species.isEmpty, !isLoading, let backend else { return }
        isLoading = true
        defer { isLoading = false }
        if let loaded = try? await backend.fishSpecies() {
            species = loaded
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
