import Backend
import DaladaCore
import Foundation
import MapEngine
import Observation

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
@MainActor
@Observable
final class MapScreenModel {
    private(set) var places: [PlaceSummary] = []
    var selectedPlace: PlaceSelection?
    var newPlace: NewPlaceRequest?
    private(set) var loadError: String?

    private let backend: BackendClient?
    private var visibleArea: GeoBoundingBox?
    private var loadTask: Task<Void, Never>?

    init(backend: BackendClient?) {
        self.backend = backend
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
    func visibleAreaChanged(_ area: GeoBoundingBox) {
        visibleArea = area
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
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            loadError = error.localizedDescription
        }
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
