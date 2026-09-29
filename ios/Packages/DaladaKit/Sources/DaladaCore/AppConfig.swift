import Foundation

/// Настройки окружения: адрес и ключ Supabase, стиль карты.
///
/// Значения приходят из Info.plist, куда их подставляет сборка из `Config/Secrets.xcconfig`.
/// Позже сюда добавится удалённая конфигурация (`config.json`), чтобы переезд бэкенда
/// не требовал обновления приложения — см. docs/03-architecture/01-ios-app.md.
public struct AppConfig: Sendable, Equatable {
    /// Адрес Supabase; `nil`, если ключи не настроены.
    public let supabaseURL: URL?
    /// Публичный ключ Supabase (publishable / anon); `nil`, если не настроен.
    public let supabaseKey: String?
    /// Стиль базовой карты.
    public let mapStyleURL: URL

    /// Бесплатная онлайн-карта на время беты (OpenFreeMap, без ключа и лимитов).
    /// Свои тайлы и офлайн-пакеты — позже.
    public static let defaultMapStyleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    public var isBackendConfigured: Bool { supabaseURL != nil && supabaseKey != nil }

    public init(supabaseURL: URL?, supabaseKey: String?, mapStyleURL: URL = AppConfig.defaultMapStyleURL) {
        self.supabaseURL = supabaseURL
        self.supabaseKey = supabaseKey
        self.mapStyleURL = mapStyleURL
    }

    /// Разбирает значения Info.plist. Ключи: `SupabaseHost`, `SupabaseKey`.
    ///
    /// `SupabaseHost` — хост без схемы (в xcconfig `//` начинает комментарий), например
    /// `abcd.supabase.co`. Для локального Supabase (`127.0.0.1:54321`, `localhost:54321`)
    /// используется http, для остальных — https.
    public init(info: [String: Any]) {
        let host = Self.cleaned(info["SupabaseHost"])
        let key = Self.cleaned(info["SupabaseKey"])
        self.init(
            supabaseURL: host.flatMap(Self.url(forHost:)),
            supabaseKey: key
        )
    }

    public static func fromMainBundle() -> AppConfig {
        AppConfig(info: Bundle.main.infoDictionary ?? [:])
    }

    /// Пустые значения и неподставленные переменные сборки (`$(SUPABASE_HOST)`) считаем отсутствующими.
    static func cleaned(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty,
              !string.hasPrefix("$(")
        else { return nil }
        return string
    }

    static func url(forHost host: String) -> URL? {
        let isLocal = host.hasPrefix("127.") || host.hasPrefix("localhost")
        return URL(string: "\(isLocal ? "http" : "https")://\(host)")
    }
}
