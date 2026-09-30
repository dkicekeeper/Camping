import DaladaCore
import Foundation
import Supabase

// MARK: - Пуш-уведомления

extension BackendClient {
    /// Этот телефон получает уведомления аккаунта (RPC `register_device`).
    public func registerDevice(token: String, environment: PushEnvironment, language: String) async throws {
        let params = ["p_token": token, "p_environment": environment.rawValue, "p_language": language]
        try await supabase.rpc("register_device", params: params).execute()
    }

    /// Этот телефон больше не получает уведомления аккаунта (перед выходом).
    public func unregisterDevice(token: String) async throws {
        try await supabase.rpc("unregister_device", params: ["p_token": token]).execute()
    }
}
