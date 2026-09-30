import DaladaCore
import Foundation
import Supabase

// MARK: - Отправка офлайн-очереди

extension BackendClient: OutboxSending {
    public var currentUserID: UUID? { supabase.auth.currentUser?.id }

    public func send(_ draft: CheckinDraft) async throws {
        try await createCheckin(draft)
    }

    public func send(_ trip: TripDraft) async throws {
        try await createTrip(trip)
    }

    /// Что делать с ошибкой отправки: ждать сеть, повторить позже, сдаться или ждать входа.
    public func failure(for error: any Error) -> SendFailure {
        Self.sendFailure(for: error)
    }

    static func sendFailure(for error: any Error) -> SendFailure {
        if error is URLError {
            return .offline
        }
        if let error = error as? AuthError {
            if case .sessionMissing = error { return .signedOut }
            return .temporary(error.localizedDescription)
        }
        if let error = error as? PostgrestError {
            switch error.code {
            case "28000":
                return .signedOut
            case .some(let code) where code.hasPrefix("PGRST3"):
                // Токен истёк или не принят — SDK обновит его к следующей попытке.
                return .temporary(error.message)
            case .some(let code) where code.hasPrefix("23") || code.hasPrefix("22"):
                // Нарушены правила данных — повтор не поможет.
                return .rejected(error.message)
            case "P0002", "42501", "54000":
                // Место или чекин не найден (удалены, скрыты), нет прав, слишком много фото
                // или слишком длинный трек.
                return .rejected(error.message)
            default:
                return .temporary(error.message)
            }
        }
        if let error = error as? StorageError {
            switch error.statusCode {
            case "400", "403", "413", "415", "422":
                return .rejected(error.message)
            default:
                return .temporary(error.message)
            }
        }
        if let error = error as? HTTPError {
            switch error.response.statusCode {
            case 401, 408, 429, 500...:
                return .temporary(error.localizedDescription)
            default:
                return .rejected(error.localizedDescription)
            }
        }
        return .temporary(error.localizedDescription)
    }
}
