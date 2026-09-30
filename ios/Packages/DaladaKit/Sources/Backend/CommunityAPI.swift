import DaladaCore
import Foundation
import Supabase

// MARK: - Отзывы

extension BackendClient {
    public func placeReviews(
        _ placeID: UUID,
        sort: ReviewSort = .new,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> [PlaceReview] {
        try await supabase
            .rpc("place_reviews", params: PlaceReviewsParams(place: placeID, order: sort.rawValue, limit: limit, offset: offset))
            .execute()
            .value
    }

    /// Сводка отзывов. `nil` — место не публичное: отзывов у него нет.
    public func reviewSummary(_ placeID: UUID) async throws -> ReviewSummary? {
        let rows: [ReviewSummary] = try await supabase
            .rpc("place_review_summary", params: ["p_place": placeID])
            .execute()
            .value
        return rows.first
    }

    /// Новый отзыв или правка своего. Возвращает id отзыва.
    @discardableResult
    public func saveReview(_ draft: ReviewDraft) async throws -> UUID {
        try await supabase
            .rpc("save_review", params: SaveReviewParams(draft))
            .execute()
            .value
    }

    public func deleteReview(_ reviewID: UUID) async throws {
        try await supabase.rpc("delete_review", params: ["p_review": reviewID]).execute()
    }
}

struct PlaceReviewsParams: Encodable, Sendable {
    let place: UUID
    let order: String
    let limit: Int
    let offset: Int

    enum CodingKeys: String, CodingKey {
        case place = "p_place"
        case order = "p_order"
        case limit = "p_limit"
        case offset = "p_offset"
    }
}

struct SaveReviewParams: Encodable, Sendable {
    let place: UUID
    let rating: Int
    let body: String?
    let visitedOn: CalendarDay

    init(_ draft: ReviewDraft) {
        place = draft.placeID
        rating = draft.rating
        let body = draft.trimmedBody
        self.body = body.isEmpty ? nil : body
        visitedOn = draft.visitedOn
    }

    enum CodingKeys: String, CodingKey {
        case place = "p_place"
        case rating = "p_rating"
        case body = "p_body"
        case visitedOn = "p_visited_on"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(place, forKey: .place)
        try c.encode(rating, forKey: .rating)
        try c.encode(body, forKey: .body)
        try c.encode(visitedOn, forKey: .visitedOn)
    }
}

// MARK: - Обсуждения

extension BackendClient {
    /// Обсуждения места, свежие по активности сверху.
    public func placeThreads(_ placeID: UUID, limit: Int = 20, offset: Int = 0) async throws -> [ThreadSummary] {
        try await supabase
            .rpc("place_threads", params: PlaceThreadsParams(place: placeID, limit: limit, offset: offset))
            .execute()
            .value
    }

    /// Обсуждение целиком. `nil` — удалено или не видно.
    public func thread(_ threadID: UUID) async throws -> ThreadDetails? {
        let rows: [ThreadDetails] = try await supabase
            .rpc("thread_view", params: ["p_thread": threadID])
            .execute()
            .value
        return rows.first
    }

    /// Ответы по порядку; `after` — последний показанный ответ (следующая страница).
    public func threadPosts(_ threadID: UUID, limit: Int = 50, after last: ThreadPost? = nil) async throws -> [ThreadPost] {
        try await supabase
            .rpc("thread_posts", params: ThreadPostsParams(thread: threadID, limit: limit, after: last))
            .execute()
            .value
    }

    public func createThread(_ draft: ThreadDraft) async throws {
        do {
            try await supabase.from("threads").insert(ThreadInsert(draft), returning: .minimal).execute()
        } catch let error as PostgrestError where error.code == "23505" {
            return
        }
    }

    public func deleteThread(_ threadID: UUID) async throws {
        try await supabase
            .from("threads")
            .update(["deleted_at": PostgresTimestamp.string(Date())])
            .eq("id", value: threadID)
            .execute()
    }

    public func createPost(_ draft: PostDraft) async throws {
        do {
            try await supabase.from("thread_posts").insert(PostInsert(draft), returning: .minimal).execute()
        } catch let error as PostgrestError where error.code == "23505" {
            return
        }
    }

    public func deletePost(_ postID: UUID) async throws {
        try await supabase
            .from("thread_posts")
            .update(["deleted_at": PostgresTimestamp.string(Date())])
            .eq("id", value: postID)
            .execute()
    }
}

struct PlaceThreadsParams: Encodable, Sendable {
    let place: UUID
    let limit: Int
    let offset: Int

    enum CodingKeys: String, CodingKey {
        case place = "p_place"
        case limit = "p_limit"
        case offset = "p_offset"
    }
}

struct ThreadPostsParams: Encodable, Sendable {
    let thread: UUID
    let limit: Int
    let after: ThreadPost?

    enum CodingKeys: String, CodingKey {
        case thread = "p_thread"
        case limit = "p_limit"
        case afterAt = "p_after_at"
        case afterID = "p_after_id"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(thread, forKey: .thread)
        try c.encode(limit, forKey: .limit)
        try c.encode(after.map { PostgresTimestamp.string($0.createdAt) }, forKey: .afterAt)
        try c.encode(after?.id, forKey: .afterID)
    }
}

struct ThreadInsert: Encodable, Sendable {
    let id: UUID
    let placeID: UUID
    let title: String
    let body: String

    init(_ draft: ThreadDraft) {
        id = draft.id
        placeID = draft.placeID
        title = draft.trimmedTitle
        body = draft.trimmedBody
    }

    enum CodingKeys: String, CodingKey {
        case id
        case placeID = "place_id"
        case title
        case body
    }
}

struct PostInsert: Encodable, Sendable {
    let id: UUID
    let threadID: UUID
    let body: String
    let quotePostID: UUID?

    init(_ draft: PostDraft) {
        id = draft.id
        threadID = draft.threadID
        body = draft.trimmedBody
        quotePostID = draft.quote?.postID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case threadID = "thread_id"
        case body
        case quotePostID = "quote_post_id"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(threadID, forKey: .threadID)
        try c.encode(body, forKey: .body)
        try c.encodeIfPresent(quotePostID, forKey: .quotePostID)
    }
}

// MARK: - Реакции

extension BackendClient {
    /// Поставить или снять реакцию. Возвращает, сколько их теперь у объекта.
    @discardableResult
    public func setReaction(_ key: ReactionKey, on: Bool) async throws -> Int {
        try await supabase
            .rpc("set_reaction", params: SetReactionParams(kind: key.kind, target: key.id, on: on))
            .execute()
            .value
    }

    /// Реакции к списку объектов; невидимые объекты в ответ не попадают.
    public func reactionSummary(_ keys: [ReactionKey]) async throws -> [ReactionKey: ReactionState] {
        let unique = Array(Set(keys)).prefix(200)
        guard !unique.isEmpty else { return [:] }
        let rows: [ReactionSummaryRow] = try await supabase
            .rpc("reaction_summary", params: ReactionSummaryParams(keys: Array(unique)))
            .execute()
            .value
        return Dictionary(rows.map { ($0.key, $0.state) }, uniquingKeysWith: { first, _ in first })
    }
}

struct SetReactionParams: Encodable, Sendable {
    let kind: ReactionTarget
    let target: UUID
    let on: Bool

    enum CodingKeys: String, CodingKey {
        case kind = "p_kind"
        case target = "p_target"
        case on = "p_on"
    }
}

struct ReactionSummaryParams: Encodable, Sendable {
    let kinds: [ReactionTarget]
    let ids: [UUID]

    init(keys: [ReactionKey]) {
        kinds = keys.map(\.kind)
        ids = keys.map(\.id)
    }

    enum CodingKeys: String, CodingKey {
        case kinds = "p_kinds"
        case ids = "p_ids"
    }
}

// MARK: - Ошибки

extension CommunityRefusal {
    /// Отказ базы из ошибки запроса (коды DL001–DL003); `nil` — другая ошибка.
    public init?(_ error: any Error) {
        guard let error = error as? PostgrestError, let code = error.code else { return nil }
        self.init(rawValue: code)
    }
}
