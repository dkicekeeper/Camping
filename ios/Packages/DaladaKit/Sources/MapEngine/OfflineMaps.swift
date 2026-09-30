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

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .MLNOfflinePackProgressChanged, object: nil, queue: .main) { note in
            guard let pack = note.object as? MLNOfflinePack else { return }
            MainActor.assumeIsolated { self.update(pack) }
        })
        observers.append(center.addObserver(forName: .MLNOfflinePackError, object: nil, queue: .main) { note in
            guard let pack = note.object as? MLNOfflinePack,
                  let id = Self.regionID(of: pack) else { return }
            let error = note.userInfo?[MLNOfflinePackUserInfoKey.error] as? NSError
            MainActor.assumeIsolated {
                self.states[id] = .failed(error?.localizedDescription ?? "")
            }
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
            MainActor.assumeIsolated {
                if let pack {
                    self.packs[region.id] = pack
                    pack.resume()
                } else {
                    self.states[region.id] = .failed(error?.localizedDescription ?? "")
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

    private static func regionID(of pack: MLNOfflinePack) -> String? {
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

    private func update(_ pack: MLNOfflinePack) {
        guard let id = Self.regionID(of: pack) else { return }
        let progress = pack.progress
        let expected = max(progress.countOfResourcesExpected, 1)
        let share = min(Double(progress.countOfResourcesCompleted) / Double(expected), 1)
        let bytes = Int64(progress.countOfBytesCompleted)
        switch pack.state {
        case .complete:
            states[id] = .downloaded(bytes: bytes)
        case .active:
            states[id] = .downloading(progress: share, bytes: bytes)
        case .inactive:
            states[id] = share >= 1 && progress.countOfResourcesExpected > 0
                ? .downloaded(bytes: bytes)
                : .paused(progress: share, bytes: bytes)
        case .unknown:
            break
        case .invalid:
            states[id] = nil
        @unknown default:
            break
        }
    }
}
