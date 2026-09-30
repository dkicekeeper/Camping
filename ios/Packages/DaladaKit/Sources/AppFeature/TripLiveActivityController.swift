import ActivityKit
import DaladaCore
import Foundation
import TripLiveActivity

/// Запускает, обновляет и завершает Live Activity записи поездки.
/// Дистанция обновляется не чаще раза в 15 секунд — время на экране идёт само.
@MainActor
final class TripLiveActivityController {
    private var activity: Activity<TripActivityAttributes>?
    private var lastState: TripActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast

    static let updateInterval: TimeInterval = 15

    func start(activity kind: TripActivity, startedAt: Date, distanceM: Double, isPaused: Bool) {
        let state = Self.state(distanceM: distanceM, isPaused: isPaused)
        // После перезапуска приложения Live Activity могла остаться — продолжаем её.
        if let existing = Activity<TripActivityAttributes>.activities.first {
            activity = existing
            push(state)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = TripActivityAttributes(
            title: String(localized: String.LocalizationValue(kind.titleKey)),
            systemImage: kind.systemImage,
            startedAt: startedAt
        )
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        lastState = state
        lastUpdate = Date()
    }

    /// `force` — сразу (пауза, продолжение); иначе не чаще `updateInterval`.
    func update(distanceM: Double, isPaused: Bool, force: Bool = false) {
        let state = Self.state(distanceM: distanceM, isPaused: isPaused)
        guard state != lastState else { return }
        guard force || Date().timeIntervalSince(lastUpdate) >= Self.updateInterval else { return }
        push(state)
    }

    func end() {
        let activities = Activity<TripActivityAttributes>.activities
        activity = nil
        lastState = nil
        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func push(_ state: TripActivityAttributes.ContentState) {
        guard let activity else { return }
        lastState = state
        lastUpdate = Date()
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private static func state(distanceM: Double, isPaused: Bool) -> TripActivityAttributes.ContentState {
        TripActivityAttributes.ContentState(
            distanceText: TripFormat.distance(distanceM),
            statusText: isPaused ? String(localized: "trip.paused") : nil
        )
    }
}
