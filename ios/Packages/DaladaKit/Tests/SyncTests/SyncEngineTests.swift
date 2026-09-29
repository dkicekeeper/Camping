import DaladaCore
import Foundation
import Persistence
import Synchronization
import Sync
import Testing

/// Подставной сервер: запоминает отправленное, отвечает заданными ошибками.
final class FakeSender: CheckinSending {
    enum Outcome: Sendable {
        case accept
        case fail(SendFailure)
    }

    struct State {
        var userID: UUID?
        var outcomes: [Outcome] = []
        var sent: [UUID] = []
        var attempts = 0
    }

    let state: Mutex<State>

    init(userID: UUID? = UUID()) {
        state = Mutex(State(userID: userID))
    }

    /// Ответы на следующие попытки по порядку; когда закончатся — принимать.
    func script(_ outcomes: Outcome...) {
        state.withLock { $0.outcomes = outcomes }
    }

    var sent: [UUID] { state.withLock { $0.sent } }
    var attempts: Int { state.withLock { $0.attempts } }

    var currentUserID: UUID? { state.withLock { $0.userID } }

    func send(_ draft: CheckinDraft) async throws {
        let outcome: Outcome = state.withLock { state in
            state.attempts += 1
            return state.outcomes.isEmpty ? .accept : state.outcomes.removeFirst()
        }
        switch outcome {
        case .accept:
            state.withLock { $0.sent.append(draft.id) }
        case .fail(let failure):
            throw FakeError(failure: failure)
        }
    }

    func failure(for error: any Error) -> SendFailure {
        (error as? FakeError)?.failure ?? .temporary("unknown")
    }
}

struct FakeError: Error {
    let failure: SendFailure
}

/// Часы, которые двигает тест.
final class TestClock: Sendable {
    private let current = Mutex(Date(timeIntervalSince1970: 1_790_000_000))
    var now: Date { current.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

@MainActor
@Suite("SyncEngine")
struct SyncEngineTests {
    let sender = FakeSender()
    let clock = TestClock()
    let engine: SyncEngine

    init() throws {
        let clock = clock
        engine = SyncEngine(outbox: try LocalDatabase.inMemory().outbox, sender: sender, now: { clock.now })
    }

    private func draft(minutesAgo: Double = 0) -> CheckinDraft {
        CheckinDraft(placeID: UUID(), at: clock.now.addingTimeInterval(-minutesAgo * 60), catches: [CatchDraft(speciesID: "pike")])
    }

    @Test func sendsRightAwayWhenOnline() async throws {
        let item = draft()
        try await engine.submit(item, placeName: "Капшагай")
        await engine.waitUntilIdle()
        #expect(sender.sent == [item.id])
        #expect(engine.pending.isEmpty)
        #expect(engine.sentCount == 1)
    }

    @Test func keepsCheckinOfflineAndSendsWhenNetworkReturns() async throws {
        sender.script(.fail(.offline))
        let item = draft()
        try await engine.submit(item, placeName: "Капшагай")
        await engine.waitUntilIdle()
        #expect(sender.sent.isEmpty)
        #expect(engine.pending.map(\.id) == [item.id])
        #expect(engine.pending.first?.state == .waiting)
        #expect(engine.pending.first?.placeName == "Капшагай")

        // Появилась сеть — отправляем, не дожидаясь паузы.
        engine.kick(force: true)
        await engine.waitUntilIdle()
        #expect(sender.sent == [item.id])
        #expect(engine.pending.isEmpty)
    }

    @Test func offlineStopsTheWholeQueue() async throws {
        sender.script(.fail(.offline))
        let first = draft(minutesAgo: 10)
        let second = draft()
        try await engine.submit(first, placeName: "Место")
        await engine.waitUntilIdle()
        try await engine.submit(second, placeName: "Место")
        await engine.waitUntilIdle()
        // Второй ушёл сразу (сеть «появилась»), первый ждёт своей паузы.
        #expect(sender.sent == [second.id])

        clock.advance(RetryPolicy.delay(afterAttempt: 1))
        engine.kick()
        await engine.waitUntilIdle()
        #expect(sender.sent == [second.id, first.id])
    }

    @Test func rejectedCheckinWaitsForUser() async throws {
        sender.script(.fail(.rejected("place not found")))
        let item = draft()
        try await engine.submit(item, placeName: "Место")
        await engine.waitUntilIdle()
        #expect(engine.pending.first?.state == .failed("place not found"))

        // Сам не повторяет даже при появлении сети.
        engine.kick(force: true)
        await engine.waitUntilIdle()
        #expect(sender.attempts == 1)

        await engine.retry(item.id)
        await engine.waitUntilIdle()
        #expect(sender.sent == [item.id])
        #expect(engine.pending.isEmpty)
    }

    @Test func temporaryErrorsGiveUpAfterLimit() async throws {
        let failures = Array(repeating: FakeSender.Outcome.fail(.temporary("503")), count: RetryPolicy.maxTemporaryAttempts)
        sender.state.withLock { $0.outcomes = failures }
        let item = draft()
        try await engine.submit(item, placeName: "Место")
        await engine.waitUntilIdle()
        for attempt in 1..<RetryPolicy.maxTemporaryAttempts {
            #expect(engine.pending.first?.state == .waiting)
            clock.advance(RetryPolicy.delay(afterAttempt: attempt))
            engine.kick()
            await engine.waitUntilIdle()
        }
        #expect(sender.attempts == RetryPolicy.maxTemporaryAttempts)
        #expect(engine.pending.first?.state == .failed("503"))
    }

    @Test func discardRemovesWithoutSending() async throws {
        sender.script(.fail(.offline))
        let item = draft()
        try await engine.submit(item, placeName: "Место")
        await engine.waitUntilIdle()
        await engine.discard(item.id)
        #expect(engine.pending.isEmpty)
        engine.kick(force: true)
        await engine.waitUntilIdle()
        #expect(sender.sent.isEmpty)
    }

    @Test func guestCannotSubmit() async throws {
        let guest = FakeSender(userID: nil)
        let engine = SyncEngine(outbox: try LocalDatabase.inMemory().outbox, sender: guest)
        await #expect(throws: SyncEngine.SubmitError.signedOut) {
            try await engine.submit(draft(), placeName: "Место")
        }
    }

    @Test func eachUserSeesOwnQueue() async throws {
        sender.script(.fail(.offline))
        try await engine.submit(draft(), placeName: "Место")
        await engine.waitUntilIdle()
        #expect(engine.pending.count == 1)

        sender.state.withLock { $0.userID = UUID() }
        await engine.refresh()
        #expect(engine.pending.isEmpty)
    }
}

@Suite("RetryPolicy")
struct RetryPolicyTests {
    @Test func backoffDoublesAndCaps() {
        #expect(RetryPolicy.delay(afterAttempt: 1) == 15)
        #expect(RetryPolicy.delay(afterAttempt: 2) == 30)
        #expect(RetryPolicy.delay(afterAttempt: 3) == 60)
        #expect(RetryPolicy.delay(afterAttempt: 50) == 900)
    }
}
