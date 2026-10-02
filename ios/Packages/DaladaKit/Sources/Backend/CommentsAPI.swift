import DaladaCore
import Foundation
import Supabase

// MARK: - Комментарии к постам

extension BackendClient {
    /// Комментарии поста, которые видит зритель (RPC `post_comments`), старые сверху.
    public func postComments(_ key: ReactionKey, limit: Int = 100) async throws -> [PostComment] {
        try await supabase
            .rpc("post_comments", params: PostCommentsParams(kind: key.kind, target: key.id, limit: limit))
            .execute()
            .value
    }

    /// Отправить комментарий. Повтор с тем же `id` (сеть оборвалась после записи) — не ошибка.
    public func addComment(_ draft: CommentDraft) async throws {
        do {
            try await supabase.from("comments").insert(CommentInsert(draft), returning: .minimal).execute()
        } catch let error as PostgrestError where error.code == "23505" {
            return
        }
    }

    /// Удалить свой комментарий или комментарий под своим постом.
    public func deleteComment(_ commentID: UUID) async throws {
        try await supabase.rpc("delete_comment", params: ["p_comment": commentID]).execute()
    }

    /// Сколько комментариев у постов; невидимые посты в ответ не попадают.
    public func commentSummary(_ keys: [ReactionKey]) async throws -> [ReactionKey: Int] {
        let unique = Array(Set(keys.filter { CommentDraft.canComment($0.kind) })).prefix(200)
        guard !unique.isEmpty else { return [:] }
        let rows: [CommentSummaryRow] = try await supabase
            .rpc("comment_summary", params: ReactionSummaryParams(keys: Array(unique)))
            .execute()
            .value
        return Dictionary(rows.map { ($0.key, $0.count) }, uniquingKeysWith: { first, _ in first })
    }
}

struct PostCommentsParams: Encodable, Sendable {
    let kind: ReactionTarget
    let target: UUID
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case kind = "p_kind"
        case target = "p_target"
        case limit = "p_limit"
    }
}

struct CommentInsert: Encodable, Sendable {
    let id: UUID
    let targetKind: ReactionTarget
    let targetID: UUID
    let body: String

    init(_ draft: CommentDraft) {
        id = draft.id
        targetKind = draft.target.kind
        targetID = draft.target.id
        body = draft.trimmedBody
    }

    enum CodingKeys: String, CodingKey {
        case id
        case targetKind = "target_kind"
        case targetID = "target_id"
        case body
    }
}
