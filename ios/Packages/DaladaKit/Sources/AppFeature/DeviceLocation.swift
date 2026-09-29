import CoreLocation
import DaladaCore

/// Разовое получение текущей позиции (для подтверждения чекина).
/// Запись треков в фоне — отдельный модуль в M3.
@MainActor
enum DeviceLocation {
    /// Текущая позиция с точностью не хуже 200 м или `nil`: нет разрешения, нет сигнала,
    /// истёк `timeout`.
    static func current(timeout: Duration = .seconds(10)) async -> GeoPoint? {
        // Сессия держит разрешение «При использовании» и при необходимости показывает запрос.
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }

        return await withTaskGroup(of: GeoPoint?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if update.authorizationDenied || update.authorizationDeniedGlobally {
                            return nil
                        }
                        if let location = update.location, location.horizontalAccuracy <= 200 {
                            return GeoPoint(
                                latitude: location.coordinate.latitude,
                                longitude: location.coordinate.longitude
                            )
                        }
                    }
                } catch {
                    return nil
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
