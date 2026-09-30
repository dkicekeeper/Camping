import Backend
import DaladaCore
import DesignTokens
import Foundation
import Persistence

/// Зависимости приложения, которые передаются экранам.
public struct AppEnvironment: Sendable {
    public let config: AppConfig
    /// `nil`, если Supabase не настроен (нет `Config/Secrets.xcconfig`).
    public let backend: BackendClient?
    /// Локальная база: офлайн-очередь и кэш.
    public let database: LocalDatabase

    public init(config: AppConfig, backend: BackendClient?, database: LocalDatabase) {
        self.config = config
        self.backend = backend
        self.database = database
    }

    public var cache: CacheStore { database.cache }

    /// Боевые зависимости из Info.plist.
    public static func live() -> AppEnvironment {
        let config = AppConfig.fromMainBundle()
        return AppEnvironment(config: config, backend: BackendClient(config: config), database: openDatabase())
    }

    /// Для превью: без бэкенда, база в памяти.
    public static let preview = AppEnvironment(config: AppConfig(info: [:]), backend: nil, database: memoryDatabase())

    /// Файл базы; если он не открылся (нет места, повреждён) — база в памяти, чтобы приложение
    /// работало, пусть и без офлайна.
    private static func openDatabase() -> LocalDatabase {
        (try? LocalDatabase.openDefault()) ?? memoryDatabase()
    }

    private static func memoryDatabase() -> LocalDatabase {
        do {
            return try LocalDatabase.inMemory()
        } catch {
            fatalError("Не удалось создать базу в памяти: \(error)")
        }
    }
}

/// Отправитель, когда сервер не настроен: очередь ничего не отправляет.
struct UnavailableSender: OutboxSending {
    var currentUserID: UUID? { nil }

    func send(_ draft: CheckinDraft) async throws {
        throw URLError(.cannotFindHost)
    }

    func send(_ trip: TripDraft) async throws {
        throw URLError(.cannotFindHost)
    }

    func failure(for error: any Error) -> SendFailure { .signedOut }
}

/// Действия при запуске приложения — вызываются один раз из `App.init()`.
public enum AppBootstrap {
    @MainActor
    public static func configure() {
        // Шрифт Inter из DesignKit должен быть зарегистрирован до первого экрана.
        DesignKitFonts.registerIfNeeded()
    }
}
