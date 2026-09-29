import DaladaCore
import Foundation
import Supabase

/// Состояние соединения с бэкендом (для экрана профиля и диагностики в бете).
public enum ConnectionState: Sendable, Equatable {
    case notConfigured
    case checking
    case connected
    case failed(String)
}

/// Единственная точка доступа к Supabase. Фичи работают с ним, а не с SDK напрямую.
public final class BackendClient: Sendable {
    let supabase: SupabaseClient

    /// `nil`, если в конфигурации нет адреса или ключа Supabase.
    public init?(config: AppConfig) {
        guard let url = config.supabaseURL, let key = config.supabaseKey else { return nil }
        supabase = SupabaseClient(supabaseURL: url, supabaseKey: key)
    }

    /// Проверяет, что сервер отвечает и миграции применены: вызывает публичную RPC
    /// `places_in_bbox` на крошечной области (доступна и гостю).
    public func checkConnection() async -> ConnectionState {
        let probe = BoundingBoxParams(minLon: 76.88, minLat: 43.23, maxLon: 76.89, maxLat: 43.24, maxResults: 1)
        do {
            _ = try await supabase.rpc("places_in_bbox", params: probe).execute()
            return .connected
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// Параметры RPC `places_in_bbox` (имена — как в SQL).
struct BoundingBoxParams: Encodable, Sendable {
    let minLon: Double
    let minLat: Double
    let maxLon: Double
    let maxLat: Double
    let maxResults: Int

    enum CodingKeys: String, CodingKey {
        case minLon = "min_lon"
        case minLat = "min_lat"
        case maxLon = "max_lon"
        case maxLat = "max_lat"
        case maxResults = "max_results"
    }
}
