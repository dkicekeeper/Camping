import Foundation

/// Условия использования, правила сообщества, политика конфиденциальности и поддержка — страницы
/// на GitHub Pages (`docs/public` в репозитории), по разделу на каждый язык.
public enum LegalDocuments {
    /// Версия документов, которую нужно принять. Увеличивается при существенных изменениях —
    /// тогда приложение попросит согласие ещё раз.
    public static let version = 1

    public static let supportEmail = "dakacom@gmail.com"

    static let baseURL = URL(string: "https://dkicekeeper.github.io/Dalada/")!

    public static func privacyPolicy(language: String) -> URL { page("privacy-policy.html", language) }

    public static func terms(language: String) -> URL { page("terms-of-use.html", language) }

    public static func support(language: String) -> URL { page("support.html", language) }

    /// Письмо в поддержку с темой «Dalada».
    public static var supportMailURL: URL { URL(string: "mailto:\(supportEmail)?subject=Dalada")! }

    /// Раздел страницы на языке `language` (незнакомый язык — русский).
    private static func page(_ name: String, _ language: String) -> URL {
        let section = ["ru", "kk", "en"].contains(language) ? language : "ru"
        return URL(string: "\(name)#\(section)", relativeTo: baseURL)!.absoluteURL
    }
}
