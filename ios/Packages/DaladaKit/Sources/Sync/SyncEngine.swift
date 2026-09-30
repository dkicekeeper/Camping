import DaladaCore
import Foundation
import Observation
import Persistence

/// Отправка офлайн-очереди. Чекин или поездка сначала сохраняются на телефоне, потом уходят
/// на сервер — сразу, если есть сеть, или позже: при появлении сети, при возврате в приложение,
/// по таймеру.
@MainActor
@Observable
public final class SyncEngine {
    public enum SubmitError: Error, Equatable {
        case signedOut
    }

    /// Чекины текущего пользователя, которые ещё не приняты сервером.
    public private(set) var pending: [PendingCheckin] = []
    /// Поездки текущего пользователя, которые ещё не приняты сервером.
    public private(set) var pendingTrips: [PendingTrip] = []
    /// Растёт после каждой принятой сервером записи — экраны по нему перечитывают данные.
    public private(set) var sentCount = 0
    public private(set) var isSending = false

    private let outbox: OutboxStore
    private let sender: any OutboxSending
    private let now: @Sendable () -> Date

    @ObservationIgnored private var processTask: Task<Void, Never>?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherPass = false
    @ObservationIgnored private var forceNextPass = false

    public init(outbox: OutboxStore, sender: any OutboxSending, now: @escaping @Sendable () -> Date = { Date() }) {
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

    /// В очередь положили запись в обход `submit` (например, законченную поездку).
    public func enqueued() async {
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

    /// «Повторить» для записи, которую не удалось отправить.
    public func retry(_ id: UUID) async {
        try? await outbox.requeue(id, now: now())
        await refresh()
        kick()
    }

    /// «Удалить» запись из очереди, не отправляя.
    public func discard(_ id: UUID) async {
        try? await outbox.remove(id)
        await refresh()
    }

    /// Перечитывает очередь текущего пользователя (после входа или выхода).
    public func refresh() async {
        guard let owner = sender.currentUserID else {
            pending = []
            pendingTrips = []
            return
        }
        pending = (try? await outbox.pending(owner: owner)) ?? pending
        pendingTrips = (try? await outbox.pendingTrips(owner: owner)) ?? pendingTrips
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

        // Сначала поездки, потом чекины; каждая запись — отдельная попытка.
        while !Task.isCancelled {
            let item: (id: UUID, send: () async throws -> Void)
            if let trip = try? await outbox.dueTrips(owner: owner, now: now()).first {
                item = (trip.id, { [sender] in try await sender.send(trip) })
            } else if let checkin = try? await outbox.due(owner: owner, now: now()).first {
                item = (checkin.id, { [sender] in try await sender.send(checkin) })
            } else {
                return
            }
            guard await attempt(item.id, item.send) else { return }
            await refresh()
        }
    }

    /// Одна попытка отправки. `false` — дальше в этот раз не отправляем (нет сети или входа).
    private func attempt(_ id: UUID, _ send: () async throws -> Void) async -> Bool {
        do {
            try await send()
        } catch {
            switch sender.failure(for: error) {
            case .offline:
                // Сети нет — остальные тоже не уйдут. Ждём сеть или таймер.
                _ = try? await outbox.recordFailedAttempt(id, error: nil, now: now())
                return false
            case .temporary(let message):
                let attempts = (try? await outbox.recordFailedAttempt(id, error: message, now: now())) ?? 0
                if attempts >= RetryPolicy.maxTemporaryAttempts {
                    try? await outbox.markFailed(id, error: message)
                }
                return true
            case .rejected(let message):
                try? await outbox.markFailed(id, error: message)
                return true
            case .signedOut:
                return false
            }
        }
        do {
            try await outbox.remove(id)
        } catch {
            return false // не смогли убрать из очереди — не отправляем по кругу
        }
        sentCount += 1
        return true
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
