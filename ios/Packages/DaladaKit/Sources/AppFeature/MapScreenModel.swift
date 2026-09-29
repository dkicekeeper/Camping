import Backend
import DaladaCore
import Foundation
import MapEngine
import Observation
import Persistence

/// Выбранное место — для `.sheet(item:)`.
struct PlaceSelection: Identifiable, Hashable {
    let id: UUID
}

/// Запрос на новое место в точке — для `.sheet(item:)`.
struct NewPlaceRequest: Identifiable, Hashable {
    let id = UUID()
    let coordinate: GeoPoint
}

/// Состояние вкладки «Карта»: места в видимой области, выбранное место, новое место.
/// Без сети — последние загруженные места и свои места из кэша.
@MainActor
@Observable
final class MapScreenModel {
    private(set) var places: [PlaceSummary] = []
    var selectedPlace: PlaceSelection?
    var newPlace: NewPlaceRequest?
    private(set) var loadError: String?

    private let backend: BackendClient?
    private let cache: CacheStore?
    private var visibleArea: GeoBoundingBox?
    private var viewer: UUID?
    private var loadTask: Task<Void, Never>?

    init(backend: BackendClient?, cache: CacheStore? = nil) {
        self.backend = backend
        self.cache = cache
    }

    var mapPlaces: [MapPlace] {
        places.map {
            MapPlace(
                id: $0.id,
                coordinate: $0.coordinate,
                isOwn: $0.isOwn,
                approximateRadiusM: $0.isApproximate ? $0.radiusM : nil
            )
        }
    }

    /// Центр видимой области — куда ставить новое место по кнопке «+».
    var visibleCenter: GeoPoint { visibleArea?.center ?? .almaty }

    /// Карта сдвинулась: загружаем места через 0,3 с после последнего движения.
    func visibleAreaChanged(_ area: GeoBoundingBox, viewer: UUID?) {
        visibleArea = area
        self.viewer = viewer
        loadTask?.cancel()
        loadTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await load(area)
        }
    }

    func reload() async {
        guard let visibleArea else { return }
        await load(visibleArea)
    }

    private func load(_ area: GeoBoundingBox) async {
        guard let backend else { return }
        do {
            places = try await backend.places(in: area)
            loadError = nil
            try? await cache?.save(places, for: .mapPlaces(viewer: viewer))
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            loadError = error.localizedDescription
            if places.isEmpty {
                places = await savedPlaces()
            }
        }
    }

    /// Последние места с карты и свои места — пока нет сети.
    private func savedPlaces() async -> [PlaceSummary] {
        guard let cache else { return [] }
        var result = (try? await cache.load([PlaceSummary].self, for: .mapPlaces(viewer: viewer))) ?? []
        if let viewer, let mine = try? await cache.load([PlaceSummary].self, for: .myPlaces(viewer)) {
            let known = Set(result.map(\.id))
            result += mine.filter { !known.contains($0.id) }
        }
        return result
    }

    /// Сохраняет новое место. Возвращает текст ошибки или `nil` при успехе.
    func create(_ draft: PlaceDraft) async -> String? {
        guard let backend else { return String(localized: "backend.status.notConfigured") }
        do {
            try await backend.createPlace(draft)
            newPlace = nil
            await reload()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
