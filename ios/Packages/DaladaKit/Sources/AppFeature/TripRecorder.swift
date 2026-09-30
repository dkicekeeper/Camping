import CoreLocation
import DaladaCore
import Foundation
import Observation
import Persistence

/// Запись поездки: геопозиция в фоне, фильтр точек, итоги на лету, каждая точка — сразу на диск.
///
/// В фоне запись держит `CLBackgroundActivitySession` (хватает разрешения «При использовании»,
/// в статус-баре — синий индикатор). Если система выгрузила приложение, при следующем запуске
/// `restore()` поднимает запись с сохранёнными точками.
@MainActor
@Observable
final class TripRecorder {
    enum Phase: Equatable {
        case idle
        case recording
        case paused
    }

    private(set) var phase: Phase = .idle
    private(set) var tripID: UUID?
    private(set) var activity: TripActivity = .fishing
    private(set) var startedAt: Date?
    private(set) var stats = TrackStats()
    /// Точки для линии на карте.
    private(set) var track: [GeoPoint] = []
    /// Скорость по GPS, м/с.
    private(set) var currentSpeed: Double?
    private(set) var currentAltitude: Double?
    /// Нет разрешения на геопозицию — запись идёт без точек.
    private(set) var isLocationDenied = false

    var isActive: Bool { phase != .idle }

    private let store: TripStore
    private let filter = TrackFilter()
    @ObservationIgnored private let liveActivity = TripLiveActivityController()
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?
    @ObservationIgnored private var serviceSession: CLServiceSession?
    @ObservationIgnored private var lastAccepted: TrackPoint?
    /// Следующая точка — после паузы: от предыдущей дистанцию не считаем.
    @ObservationIgnored private var nextStartsSegment = false

    init(store: TripStore) {
        self.store = store
    }

    // MARK: - Управление

    func start(activity: TripActivity) async {
        guard phase == .idle else { return }
        let id = UUID()
        let now = Date()
        do {
            try await store.start(id: id, activity: activity, at: now)
        } catch {
            return
        }
        tripID = id
        self.activity = activity
        startedAt = now
        stats = TrackStats()
        track = []
        lastAccepted = nil
        nextStartsSegment = false
        phase = .recording
        beginUpdates()
        liveActivity.start(activity: activity, startedAt: now, distanceM: 0, isPaused: false)
    }

    func pause() async {
        guard phase == .recording else { return }
        phase = .paused
        stopUpdates()
        nextStartsSegment = true
        liveActivity.update(distanceM: stats.distanceM, isPaused: true, force: true)
        try? await store.setState(.paused)
    }

    func resume() async {
        guard phase == .paused else { return }
        phase = .recording
        liveActivity.update(distanceM: stats.distanceM, isPaused: false, force: true)
        try? await store.setState(.recording)
        beginUpdates()
    }

    /// Финиш: поездка уходит в очередь отправки. Запись на этот момент должна быть на паузе.
    func finish(owner: UUID, title: String, note: String, visibility: Visibility, activity: TripActivity, endedAt: Date) async throws {
        stopUpdates()
        try await store.finishActive(
            owner: owner,
            title: title,
            note: note,
            visibility: visibility,
            activity: activity,
            endedAt: endedAt,
            now: Date()
        )
        liveActivity.end()
        reset()
    }

    /// «Удалить поездку»: запись и точки стираются.
    func discard() async {
        stopUpdates()
        try? await store.discardActive()
        liveActivity.end()
        reset()
    }

    /// После запуска приложения: продолжить незаконченную запись.
    func restore() async {
        guard phase == .idle, let active = try? await store.active() else { return }
        tripID = active.id
        activity = active.activity
        startedAt = active.startedAt
        stats = TrackStats(points: active.points)
        track = active.points.map(\.coordinate)
        lastAccepted = active.points.last
        switch active.state {
        case .recording:
            phase = .recording
            beginUpdates()
        case .paused:
            phase = .paused
            nextStartsSegment = true
        }
        liveActivity.start(
            activity: active.activity,
            startedAt: active.startedAt,
            distanceM: stats.distanceM,
            isPaused: phase == .paused
        )
    }

    private func reset() {
        phase = .idle
        tripID = nil
        startedAt = nil
        stats = TrackStats()
        track = []
        currentSpeed = nil
        currentAltitude = nil
        lastAccepted = nil
        nextStartsSegment = false
    }

    // MARK: - Геопозиция

    private func beginUpdates() {
        stopUpdates()
        serviceSession = CLServiceSession(authorization: .whenInUse)
        backgroundSession = CLBackgroundActivitySession()
        let configuration: CLLocationUpdate.LiveConfiguration = activity == .hiking ? .fitness : .otherNavigation
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(configuration) {
                    guard let self, !Task.isCancelled else { return }
                    await self.handle(update)
                }
            } catch {
                return
            }
        }
    }

    private func stopUpdates() {
        updatesTask?.cancel()
        updatesTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        serviceSession?.invalidate()
        serviceSession = nil
    }

    private func handle(_ update: CLLocationUpdate) async {
        if update.authorizationDenied || update.authorizationDeniedGlobally {
            isLocationDenied = true
            return
        }
        guard phase == .recording, let tripID, let location = update.location else { return }
        isLocationDenied = false
        currentSpeed = location.speed >= 0 ? location.speed : nil
        currentAltitude = location.verticalAccuracy >= 0 ? location.altitude : nil

        var point = TrackPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed >= 0 ? location.speed : nil,
            timestamp: location.timestamp
        )
        // После паузы или долгого перерыва (приложение было выгружено) — новый отрезок.
        let longGap = lastAccepted.map { point.timestamp.timeIntervalSince($0.timestamp) > TrackStats.maxMovingGap } ?? false
        point.startsSegment = nextStartsSegment || longGap
        guard filter.accepts(point, after: lastAccepted) else { return }

        nextStartsSegment = false
        lastAccepted = point
        stats.add(point)
        track.append(point.coordinate)
        liveActivity.update(distanceM: stats.distanceM, isPaused: false)
        try? await store.append(point, to: tripID)
    }
}
