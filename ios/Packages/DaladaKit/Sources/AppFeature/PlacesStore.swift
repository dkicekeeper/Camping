import Backend
import CoreLocation
import DaladaCore
import Foundation
import Observation
import Persistence

/// Разрешение на геопозицию — без запроса.
enum LocationPermission {
    static var isAuthorized: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    static var isUndetermined: Bool {
        CLLocationManager().authorizationStatus == .notDetermined
    }
}

/// Подборки вкладки «Места» (RPC `places_discover`), моя позиция для «Рядом» и превью фото.
/// Без сети — сохранённая копия.
@MainActor
@Observable
final class PlacesStore {
    private(set) var discovery = PlaceDiscovery()
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var isShowingSavedCopy = false
    /// Где я — для «Рядом» и расстояний. Спрашиваем, только если разрешение уже есть или человек
    /// сам нажал «Показать места рядом».
    private(set) var location: GeoPoint?
    /// Подписанные ссылки на превью: путь → ссылка (действуют час).
    private(set) var photoURLs: [String: URL] = [:]

    let backend: BackendClient?
    private let cache: CacheStore

    init(backend: BackendClient?, cache: CacheStore) {
        self.backend = backend
        self.cache = cache
    }

    /// Можно предложить «Показать места рядом»: позиции нет, а разрешение ещё не спрашивали.
    var canAskForLocation: Bool { location == nil && LocationPermission.isUndetermined }

    func load(viewer: UUID?) async {
        guard let backend else {
            hasLoaded = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        if location == nil, LocationPermission.isAuthorized {
            location = await DeviceLocation.current(timeout: .seconds(5))
        }
        let key = CacheKey.placesDiscover(viewer: viewer)
        do {
            let loaded = try await backend.placesDiscover(near: location)
            discovery = loaded
            isShowingSavedCopy = false
            loadError = nil
            hasLoaded = true
            try? await cache.save(loaded, for: key)
            await loadPhotos(for: Self.allItems(loaded))
        } catch is CancellationError {
            return
        } catch {
            if let saved = try? await cache.load(PlaceDiscovery.self, for: key) {
                discovery = saved
                isShowingSavedCopy = true
            } else {
                loadError = error.localizedDescription
            }
            hasLoaded = true
        }
    }

    /// «Показать места рядом»: системный запрос разрешения и позиция, затем подборки заново.
    func locate(viewer: UUID?) async {
        location = await DeviceLocation.current()
        await load(viewer: viewer)
    }

    /// Закладку нажали в карточке места — отметка во всех подборках.
    func setSaved(_ saved: Bool, placeID: UUID) {
        discovery.setSaved(saved, placeID: placeID)
    }

    /// Подписать ссылки на превью, которых ещё нет.
    func loadPhotos(for items: [PlaceItem]) async {
        guard let backend else { return }
        let paths = items.compactMap(\.photoPath).filter { photoURLs[$0] == nil }
        guard !paths.isEmpty,
              let urls = try? await backend.signedMediaURLs(paths: paths)
        else { return }
        photoURLs.merge(urls) { _, new in new }
    }

    static func allItems(_ discovery: PlaceDiscovery) -> [PlaceItem] {
        PlaceSection.allCases.flatMap { discovery.items($0) } + discovery.recommended.flatMap(\.places)
    }
}
