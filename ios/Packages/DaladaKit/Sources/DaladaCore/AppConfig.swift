import Foundation

/// Настройки окружения: адрес и ключ Supabase, карта.
///
/// Значения приходят из Info.plist, куда их подставляет сборка из `Config/Secrets.xcconfig`.
/// Позже сюда добавится удалённая конфигурация (`config.json`), чтобы переезд бэкенда
/// не требовал обновления приложения — см. docs/03-architecture/01-ios-app.md.
public struct AppConfig: Sendable, Equatable {
    /// Адрес Supabase; `nil`, если ключи не настроены.
    public let supabaseURL: URL?
    /// Публичный ключ Supabase (publishable / anon); `nil`, если не настроен.
    public let supabaseKey: String?
    /// Где лежит своя карта: стили, тайлы, шрифты и значки (map/README.md).
    public let mapBaseURL: URL

    /// Бакет Cloudflare R2 со своей картой (map/config.json → public_base). Когда появится
    /// домен — `tiles.dalada.app`.
    public static let defaultMapBaseURL = URL(string: "https://pub-06c03b3c9f2e4de7b1a196206e04c258.r2.dev")!
    /// Языки подписей на карте; для остальных — русский.
    public static let mapLanguages = ["ru", "kk", "en"]

    public var isBackendConfigured: Bool { supabaseURL != nil && supabaseKey != nil }

    /// Стиль карты с подписями на языке интерфейса.
    public var mapStyleURL: URL { mapStyleURL(language: Self.interfaceLanguage) }

    /// Стиль карты с подписями на языке `language` (ru, kk, en).
    public func mapStyleURL(language: String) -> URL {
        let code = Self.mapLanguages.contains(language) ? language : "ru"
        return mapBaseURL.appending(path: "styles/liberty.\(code).json")
    }

    /// Язык интерфейса приложения (учитывает язык, выбранный для приложения в Настройках iOS).
    public static var interfaceLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "ru"
    }

    public init(supabaseURL: URL?, supabaseKey: String?, mapBaseURL: URL = AppConfig.defaultMapBaseURL) {
        self.supabaseURL = supabaseURL
        self.supabaseKey = supabaseKey
        self.mapBaseURL = mapBaseURL
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
