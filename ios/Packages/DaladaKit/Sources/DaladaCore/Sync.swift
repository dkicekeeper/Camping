import Foundation

/// Почему не удалось отправить. От этого зависит, что делать с записью в очереди.
public enum SendFailure: Equatable, Sendable {
    /// Нет сети или сервер недоступен. Ждём сеть; число попыток не ограничено.
    case offline
    /// Сервер ответил ошибкой, которая может пройти (сбой, истёк токен). Несколько попыток.
    case temporary(String)
    /// Сервер отклонил данные (место удалено, нарушено правило). Повтор не поможет.
    case rejected(String)
    /// Нет входа. Отправим после входа.
    case signedOut
}

/// Отправка чекина на сервер. В приложении — `BackendClient`, в тестах — подделка.
public protocol CheckinSending: Sendable {
    /// Кто сейчас вошёл. Очередь у каждого пользователя своя.
    var currentUserID: UUID? { get }
    /// Создаёт чекин с уловами и фото. Повторная отправка того же черновика безопасна.
    func send(_ draft: CheckinDraft) async throws
    func failure(for error: any Error) -> SendFailure
}

/// Когда повторять отправку.
public enum RetryPolicy {
    /// После стольких временных ошибок подряд запись помечается «не отправлено».
    public static let maxTemporaryAttempts = 8

    /// Пауза после `attempt`-й неудачи: 15 с, 30 с, 1 мин… но не больше 15 минут.
    public static func delay(afterAttempt attempt: Int) -> TimeInterval {
        let exponent = min(max(attempt - 1, 0), 10)
        return min(15 * pow(2, Double(exponent)), 15 * 60)
    }
}

/// Чекин в очереди отправки — для интерфейса (без самих фото).
public struct PendingCheckin: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// Ждёт сети или следующей попытки.
        case waiting
        /// Сервер отклонил или ошибки повторялись — нужен выбор пользователя.
        case failed(String)
    }

    public let id: UUID
    public let placeID: UUID
    public let placeName: String
    public let at: Date
    public let conditions: CheckinConditions
    public let note: String
    /// Уловы без фото.
    public let catches: [CatchDraft]
    public let photoCount: Int
    public let state: State

    public init(
        id: UUID,
        placeID: UUID,
        placeName: String,
        at: Date,
        conditions: CheckinConditions,
        note: String,
        catches: [CatchDraft],
        photoCount: Int,
        state: State
    ) {
        self.id = id
        self.placeID = placeID
        self.placeName = placeName
        self.at = at
        self.conditions = conditions
        self.note = note
        self.catches = catches
        self.photoCount = photoCount
        self.state = state
    }
}
