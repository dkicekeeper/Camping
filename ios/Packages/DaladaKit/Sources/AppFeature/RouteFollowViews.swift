import CoreLocation
import DaladaCore
import DesignComponents
import DesignTokens
import MapEngine
import SwiftUI
import UIKit

/// Маршрут, по которому можно пройти: трек поездки (своей или друга).
struct FollowedRoute: Identifiable, Hashable {
    let id: UUID
    let segments: [[GeoPoint]]

    init?(trip: TripDetails) {
        guard RouteFollower(segments: trip.segments) != nil else { return nil }
        id = trip.summary.id
        segments = trip.segments
    }
}

/// Следование по маршруту: геопозиция → где человек на маршруте; вибрация при сходе и на финише.
/// Работает без сети: маршрут уже на телефоне, карта — из скачанных районов и кэша.
@MainActor
@Observable
final class RouteFollowSession {
    let route: FollowedRoute
    private(set) var isReversed = false
    private(set) var progress: RouteProgress?
    private(set) var isLocationDenied = false

    @ObservationIgnored private var follower: RouteFollower?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var serviceSession: CLServiceSession?
    @ObservationIgnored private let feedback = UINotificationFeedbackGenerator()

    init(route: FollowedRoute) {
        self.route = route
        follower = RouteFollower(segments: route.segments)
    }

    /// Откуда идти (с учётом направления).
    var startPoint: GeoPoint? { follower?.points.first }

    func start() {
        stop()
        serviceSession = CLServiceSession(authorization: .whenInUse)
        feedback.prepare()
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    guard let self, !Task.isCancelled else { return }
                    self.handle(update)
                }
            } catch {
                return
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        serviceSession?.invalidate()
        serviceSession = nil
    }

    /// Пройти маршрут в обратную сторону (или вернуть прямое направление).
    func reverse() {
        isReversed.toggle()
        follower = RouteFollower(segments: route.segments, reversed: isReversed)
        progress = nil
    }

    private func handle(_ update: CLLocationUpdate) {
        if update.authorizationDenied || update.authorizationDeniedGlobally {
            isLocationDenied = true
            return
        }
        guard let location = update.location,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100,
              var follower else { return }
        isLocationDenied = false
        let previous = progress
        let next = follower.update(
            position: GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            accuracy: location.horizontalAccuracy
        )
        self.follower = follower
        progress = next
        if next.isOffRoute && previous?.isOffRoute != true {
            feedback.notificationOccurred(.warning)
        }
        if next.isFinished && previous?.isFinished != true {
            feedback.notificationOccurred(.success)
        }
    }
}

/// Экран следования: карта с маршрутом и позицией, сверху — сколько осталось или предупреждение.
struct FollowRouteView: View {
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @Environment(TripRecorder.self) private var recorder
    @State private var session: RouteFollowSession

    init(route: FollowedRoute, environment: AppEnvironment) {
        self.environment = environment
        _session = State(initialValue: RouteFollowSession(route: route))
    }

    var body: some View {
        DaladaMapView(
            styleURL: environment.config.mapStyleURL,
            initialCenter: session.startPoint ?? .almaty,
            initialZoom: 14,
            showsUserLocation: true,
            trackSegments: recorder.isActive ? [recorder.track] : [],
            routeSegments: session.route.segments,
            cameraMode: .followUser
        )
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            status
                .padding(AppSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
                .screenPadding()
                .padding(.top, AppSpacing.sm)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: AppSpacing.md) {
                Button {
                    session.reverse()
                } label: {
                    Label(
                        session.isReversed ? "route.follow.forward" : "route.follow.reverse",
                        systemImage: "arrow.uturn.backward"
                    )
                    .frame(maxWidth: .infinity)
                }
                .secondaryButton()
                Button {
                    dismiss()
                } label: {
                    Label("route.follow.stop", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .primaryButton()
            }
            .screenPadding()
            .padding(.bottom, AppSpacing.lg)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            session.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            session.stop()
        }
    }

    @ViewBuilder
    private var status: some View {
        if session.isLocationDenied {
            Label("route.follow.denied", systemImage: "location.slash")
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.destructive)
        } else if let progress = session.progress {
            if progress.isFinished {
                Label("route.follow.finished", systemImage: "flag.checkered")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.success)
            } else if progress.isApproaching {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("route.follow.approach \(TripFormat.distance(progress.distanceToRoute))")
                        .font(AppTypography.title)
                    Text("route.follow.approach.hint")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    if progress.isOffRoute {
                        Label {
                            Text("route.follow.offRoute \(TripFormat.distance(progress.distanceToRoute))")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColors.destructive)
                    }
                    Text("route.follow.remaining \(TripFormat.distance(progress.remaining))")
                        .font(AppTypography.title)
                    ProgressView(value: progress.fraction)
                    Text("route.follow.traveled \(TripFormat.distance(progress.traveled)) \(TripFormat.distance(progress.total))")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        } else {
            HStack(spacing: AppSpacing.sm) {
                ProgressView()
                Text("route.follow.locating")
                    .font(AppTypography.bodyEmphasis)
            }
        }
    }
}
