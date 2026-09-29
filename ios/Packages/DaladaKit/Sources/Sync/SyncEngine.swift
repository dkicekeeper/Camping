import DaladaCore
import Foundation
import Observation
import Persistence

/// Отправка офлайн-очереди. Чекин сначала сохраняется на телефоне, потом уходит на сервер —
/// сразу, если есть сеть, или позже: при появлении сети, при возврате в приложение, по таймеру.
@MainActor
@Observable
public final class SyncEngine {
    public enum SubmitError: Error, Equatable {
        case signedOut
    }

    /// Чекины текущего пользователя, которые ещё не приняты сервером.
    public private(set) var pending: [PendingCheckin] = []
    /// Растёт после каждого принятого сервером чекина — экраны по нему перечитывают данные.
    public private(set) var sentCount = 0
    public private(set) var isSending = false

    private let outbox: OutboxStore
    private let sender: any CheckinSending
    private let now: @Sendable () -> Date

    @ObservationIgnored private var processTask: Task<Void, Never>?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherPass = false
    @ObservationIgnored private var forceNextPass = false

    public init(outbox: OutboxStore, sender: any CheckinSending, now: @escaping @Sendable () -> Date = { Date() }) {
        self.outbox = outbox
        self.sender = sender
        self.now = now
    }

    /// Сохраняет чекин в очередь и сразу начинает отправку. Возвращается, как только чекин
    /// сохранён на телефоне, — не дожидаясь сети.
    public func submit(_ draft: CheckinDraft, placeName: String) async throws {
        guard let owner = sender.currentUserID else { throw SubmitError.signedOut }
        try await outbox.enqueue(draft, owner: owner, placeName: placeName, now: now())
        await refresh()
        kick()
    }

    /// Пора отправлять. `force` — не ждать паузы между попытками (появилась сеть, открыли
    /// приложение, вошли в аккаунт).
    public func kick(force: Bool = false) {
        forceNextPass = forceNextPass || force
        if processTask != nil {
            needsAnotherPass = true
            return
        }
        processTask = Task { [weak self] in
            await self?.run()
        }
    }

    /// Дождаться окончания текущей отправки (для тестов и фоновых задач).
    public func waitUntilIdle() async {
        while let task = processTask {
            await task.value
        }
    }

    /// «Повторить» для чекина, который не удалось отправить.
    public func retry(_ id: UUID) async {
        try? await outbox.requeue(id, now: now())
        await refresh()
        kick()
    }

    /// «Удалить» чекин из очереди, не отправляя.
    public func discard(_ id: UUID) async {
        try? await outbox.remove(id)
        await refresh()
    }

    /// Перечитывает очередь текущего пользователя (после входа или выхода).
    public func refresh() async {
        guard let owner = sender.currentUserID else {
            pending = []
            return
        }
        pending = (try? await outbox.pending(owner: owner)) ?? pending
    }

    // MARK: - Отправка

    private func run() async {
        repeat {
            needsAnotherPass = false
            let force = forceNextPass
            forceNextPass = false
            await sendDue(force: force)
        } while needsAnotherPass
        await refresh()
        await scheduleWake()
        processTask = nil
    }

    private func sendDue(force: Bool) async {
        guard let owner = sender.currentUserID else { return }
        if force {
            try? await outbox.makeDue(owner: owner, now: now())
        }
        isSending = true
        defer { isSending = false }

        while !Task.isCancelled {
            guard let draft = try? await outbox.due(owner: owner, now: now()).first else { return }
            do {
                try await sender.send(draft)
                do {
                    try await outbox.remove(draft.id)
                } catch {
                    return // не смогли убрать из очереди — не отправляем по кругу
                }
                sentCount += 1
            } catch {
                switch sender.failure(for: error) {
                case .offline:
                    // Сети нет — остальные тоже не уйдут. Ждём сеть или таймер.
                    _ = try? await outbox.recordFailedAttempt(draft.id, error: nil, now: now())
                    return
                case .temporary(let message):
                    let attempts = (try? await outbox.recordFailedAttempt(draft.id, error: message, now: now())) ?? 0
                    if attempts >= RetryPolicy.maxTemporaryAttempts {
                        try? await outbox.markFailed(draft.id, error: message)
                    }
                case .rejected(let message):
                    try? await outbox.markFailed(draft.id, error: message)
                case .signedOut:
                    return
                }
            }
            await refresh()
        }
    }

    /// Будильник на следующую попытку по паузе из `RetryPolicy`.
    private func scheduleWake() async {
        wakeTask?.cancel()
        wakeTask = nil
        guard let owner = sender.currentUserID,
              let next = try? await outbox.nextAttemptDate(owner: owner)
        else { return }
        let delay = max(next.timeIntervalSince(now()), 1)
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.kick()
        }
    }
}
