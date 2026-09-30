import BackgroundTasks
import DaladaCore
import Foundation
import Sync
import UIKit

/// Офлайн-очередь, когда приложение не на экране. Свернули приложение — досылаем то, что пора
/// (система даёт до ~30 секунд). Если в очереди что-то осталось, просим систему разбудить
/// приложение позже (`BGAppRefreshTask`): там отправляется всё, что ждёт, — например, чекины
/// с водоёма, когда телефон снова в сети. Время выбирает система; без сети запись подождёт.
@MainActor
public final class BackgroundSync {
    /// Идентификатор фонового обновления — тот же в Info.plist (`BGTaskSchedulerPermittedIdentifiers`).
    public static let refreshTaskID = "app.dalada.ios.sync"

    /// Очередь отправки — одна на приложение: её используют и экраны, и фоновые задачи.
    let engine: SyncEngine

    private var finishing: Task<Void, Never>?
    private var finishingTaskID: UIBackgroundTaskIdentifier = .invalid

    public init(environment: AppEnvironment) {
        let sender: any OutboxSending
        if let backend = environment.backend {
            sender = backend
        } else {
            sender = UnavailableSender()
        }
        engine = SyncEngine(outbox: environment.database.outbox, sender: sender)
    }

    /// Фоновое обновление от системы (`.backgroundTask(.appRefresh(…))` в `App`).
    public func runRefresh() async {
        await engine.flush(force: true)
        updateRefreshRequest()
    }

    /// Приложение свернули: дослать начатое, пока система даёт время.
    func didEnterBackground() {
        updateRefreshRequest()
        guard engine.hasWaiting || engine.isSending, finishing == nil else { return }
        finishingTaskID = UIApplication.shared.beginBackgroundTask(withName: "Dalada.sync") { [weak self] in
            MainActor.assumeIsolated {
                self?.endFinishing()
            }
        }
        finishing = Task { [weak self] in
            guard let engine = self?.engine else { return }
            await engine.flush(force: false)
            // Отменили — значит, время уже отпустили в `endFinishing`.
            guard !Task.isCancelled else { return }
            self?.updateRefreshRequest()
            self?.endFinishing()
        }
    }

    /// Время вышло или всё отправлено: останавливаем отправку и отпускаем фоновое время.
    private func endFinishing() {
        finishing?.cancel()
        finishing = nil
        guard finishingTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(finishingTaskID)
        finishingTaskID = .invalid
    }

    /// Пока в очереди что-то ждёт — фоновое обновление не раньше чем через 15 минут; пусто — отменяем.
    private func updateRefreshRequest() {
        guard engine.hasWaiting else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        // Не получилось (симулятор, фоновое обновление выключено в Настройках) — отправим,
        // когда приложение откроют.
        try? BGTaskScheduler.shared.submit(request)
    }
}
