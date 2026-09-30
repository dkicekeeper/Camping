import MapLibre

/// Кэш карты: тайлы, которые смотрели с сетью, остаются на телефоне и открываются без неё.
/// Районы целиком заранее — `OfflineMaps` (офлайн-пакеты со своих тайлов).
public enum MapCache {
    /// 300 МБ — несколько районов в подробном масштабе (по умолчанию у MapLibre — 50 МБ).
    public static let ambientCacheBytes: UInt = 300 * 1024 * 1024

    /// Вызывается один раз при запуске приложения.
    @MainActor
    public static func configure() {
        MLNOfflineStorage.shared.setMaximumAmbientCacheSize(ambientCacheBytes) { _ in }
    }
}
