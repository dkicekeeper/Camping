import DaladaCore
import Foundation
import Supabase

// MARK: - Согласие с условиями

extension BackendClient {
    /// Человек принял условия и политику этой версии (RPC `accept_terms`, время ставит сервер).
    public func acceptTerms(version: Int) async throws {
        try await supabase.rpc("accept_terms", params: ["p_version": version]).execute()
    }
}
