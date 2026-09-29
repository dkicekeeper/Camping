import Backend
import DaladaCore
import DesignTokens

/// Зависимости приложения, которые передаются экранам.
public struct AppEnvironment: Sendable {
    public let config: AppConfig
    /// `nil`, если Supabase не настроен (нет `Config/Secrets.xcconfig`).
    public let backend: BackendClient?

    public init(config: AppConfig, backend: BackendClient?) {
        self.config = config
        self.backend = backend
    }

    /// Боевые зависимости из Info.plist.
    public static func live() -> AppEnvironment {
        let config = AppConfig.fromMainBundle()
        return AppEnvironment(config: config, backend: BackendClient(config: config))
    }

    /// Для превью: без бэкенда.
    public static let preview = AppEnvironment(config: AppConfig(info: [:]), backend: nil)
}

/// Действия при запуске приложения — вызываются один раз из `App.init()`.
public enum AppBootstrap {
    @MainActor
    public static func configure() {
        // Шрифт Inter из DesignKit должен быть зарегистрирован до первого экрана.
        DesignKitFonts.registerIfNeeded()
    }
}
