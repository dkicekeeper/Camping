import CoreLocation
import DaladaCore
import Foundation
import MapLibre
import Observation

/// Районы карты, скачанные заранее (офлайн-пакеты MapLibre): тайлы, шрифты и значки стиля лежат
/// на телефоне и открываются без сети. Тайлы — свои, из бакета (map/README.md).
@MainActor
@Observable
public final class OfflineMaps {
    public enum State: Equatable, Sendable {
        case notDownloaded
        /// Доля скачанного 0…1 и сколько байт уже на телефоне.
        case downloading(progress: Double, bytes: Int64)
        case paused(progress: Double, bytes: Int64)
        case downloaded(bytes: Int64)
        case failed(String)
    }

    public static let shared = OfflineMaps()

    public private(set) var states: [String: State] = [:]
    /// Пакеты с телефона прочитаны (до этого список районов показывает загрузку).
    public private(set) var isLoaded = false

    @ObservationIgnored private var packs: [String: MLNOfflinePack] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var packsObservation: NSKeyValueObservation?

    // Уведомления MapLibre приходят на главном потоке (`queue: .main`). Из пакета берутся только
    // id района и состояние — в главный актор передаются значения, а не сам пакет.
    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .MLNOfflinePackProgressChanged, object: nil, queue: .main) { note in
            guard let pack = note.object as? MLNOfflinePack,
                  let id = Self.regionID(of: pack) else { return }
            let state = Self.state(of: pack)
            MainActor.assumeIsolated { self.apply(state, to: id) }
        })
        observers.append(center.addObserver(forName: .MLNOfflinePackError, object: nil, queue: .main) { note in
            guard let pack = note.object as? MLNOfflinePack,
                  let id = Self.regionID(of: pack) else { return }
            let message = (note.userInfo?[MLNOfflinePackUserInfoKey.error] as? NSError)?.localizedDescription ?? ""
            MainActor.assumeIsolated { self.states[id] = .failed(message) }
        })
        packsObservation = MLNOfflineStorage.shared.observe(\.packs, options: [.initial, .new]) { _, _ in
            MainActor.assumeIsolated { self.reloadPacks() }
        }
    }

    public func state(of region: MapRegion) -> State {
        states[region.id] ?? .notDownloaded
    }

    /// Всего на телефоне в скачанных районах.
    public var totalBytes: Int64 {
        states.values.reduce(0) { total, state in
            switch state {
            case .downloaded(let bytes), .downloading(_, let bytes), .paused(_, let bytes): total + bytes
            case .notDownloaded, .failed: total
            }
        }
    }

    /// Скачать район (или продолжить скачивание).
    public func download(_ region: MapRegion, styleURL: URL) {
        if let pack = packs[region.id] {
            pack.resume()
            return
        }
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: region.bounds.southWest.latitude, longitude: region.bounds.southWest.longitude),
            ne: CLLocationCoordinate2D(latitude: region.bounds.northEast.latitude, longitude: region.bounds.northEast.longitude)
        )
        let pyramid = MLNTilePyramidOfflineRegion(
            styleURL: styleURL,
            bounds: bounds,
            fromZoomLevel: Double(MapRegion.minZoom),
            toZoomLevel: Double(region.maxZoom)
        )
        let context = (try? JSONEncoder().encode(Context(region: region.id))) ?? Data()
        states[region.id] = .downloading(progress: 0, bytes: 0)
        MLNOfflineStorage.shared.addPack(for: pyramid, withContext: context) { pack, error in
            // Колбэк MapLibre — на главном потоке; пакет дальше живёт только там.
            nonisolated(unsafe) let pack = pack
            let error = error?.localizedDescription
            MainActor.assumeIsolated {
                if let pack {
                    self.packs[region.id] = pack
                    pack.resume()
                } else {
                    self.states[region.id] = .failed(error ?? "")
                }
            }
        }
    }

    public func pause(_ region: MapRegion) {
        packs[region.id]?.suspend()
    }

    /// Удалить скачанный район с телефона.
    public func remove(_ region: MapRegion) {
        guard let pack = packs[region.id] else {
            states[region.id] = nil
            return
        }
        pack.suspend()
        packs[region.id] = nil
        states[region.id] = nil
        MLNOfflineStorage.shared.removePack(pack) { _ in }
    }

    // MARK: - Пакеты

    private struct Context: Codable {
        var region: String
    }

    private nonisolated static func regionID(of pack: MLNOfflinePack) -> String? {
        (try? JSONDecoder().decode(Context.self, from: pack.context))?.region
    }

    private func reloadPacks() {
        let current = MLNOfflineStorage.shared.packs ?? []
        var found: [String: MLNOfflinePack] = [:]
        for pack in current {
            guard let id = Self.regionID(of: pack) else { continue }
            found[id] = pack
            pack.requestProgress()
        }
        packs = found
        for id in states.keys where found[id] == nil {
            if case .downloading = states[id] { continue } // пакет ещё создаётся
            states[id] = nil
        }
        isLoaded = MLNOfflineStorage.shared.packs != nil
    }

    /// Состояние пакета; `nil` — пока неизвестно (не менять), `.notDownloaded` — пакет удалён.
    private nonisolated static func state(of pack: MLNOfflinePack) -> State? {
        let progress = pack.progress
        let expected = max(progress.countOfResourcesExpected, 1)
        let share = min(Double(progress.countOfResourcesCompleted) / Double(expected), 1)
        let bytes = Int64(progress.countOfBytesCompleted)
        switch pack.state {
        case .complete:
            return .downloaded(bytes: bytes)
        case .active:
            return .downloading(progress: share, bytes: bytes)
        case .inactive:
            return share >= 1 && progress.countOfResourcesExpected > 0
                ? .downloaded(bytes: bytes)
                : .paused(progress: share, bytes: bytes)
        case .invalid:
            return .notDownloaded
        case .unknown:
            return nil
        @unknown default:
            return nil
        }
    }

    private func apply(_ state: State?, to id: String) {
        switch state {
        case nil: break
        case .notDownloaded?: states[id] = nil
        case let state?: states[id] = state
        }
    }
}
