import DaladaCore
import Foundation
import Supabase

// MARK: - Жалобы

extension BackendClient {
    /// Пожаловаться на контент или человека (RPC `report_content`). Повторная жалоба на тот же объект
    /// обновляет причину.
    public func report(_ target: ReportTarget, id: UUID, reason: ReportReason, note: String?) async throws {
        let params = ReportParams(pKind: target.rawValue, pTarget: id, pReason: reason.rawValue, pNote: note)
        try await supabase.rpc("report_content", params: params).execute()
    }
}

struct ReportParams: Encodable, Sendable {
    let pKind: String
    let pTarget: UUID
    let pReason: String
    let pNote: String?

    enum CodingKeys: String, CodingKey {
        case pKind = "p_kind"
        case pTarget = "p_target"
        case pReason = "p_reason"
        case pNote = "p_note"
    }
}
