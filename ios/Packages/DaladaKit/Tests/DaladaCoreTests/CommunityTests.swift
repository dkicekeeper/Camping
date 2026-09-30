import Foundation
import Testing
@testable import DaladaCore

@Suite("Community")
struct CommunityTests {
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test func calendarDayParsesAndFormats() throws {
        let day = try #require(CalendarDay(string: "2026-09-27"))
        #expect(day == CalendarDay(year: 2026, month: 9, day: 27))
        #expect(day.string == "2026-09-27")
        #expect(CalendarDay(string: "27.09.2026") == nil)
        #expect(CalendarDay(string: "2026-13-01") == nil)
        #expect(CalendarDay(year: 2026, month: 9, day: 26) < day)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        #expect(CalendarDay(day.date(calendar: calendar), calendar: calendar) == day)

        let json = try JSONEncoder().encode(["visited_on": day])
        #expect(String(decoding: json, as: UTF8.self) == #"{"visited_on":"2026-09-27"}"#)
    }

    @Test func decodesReviewsAndSummary() throws {
        let json = """
        [{"review_id": "aaaaaaaa-0000-0000-0000-000000000001", "author_id": "11111111-1111-1111-1111-111111111111",
          "author_username": "author", "author_display_name": null, "author_avatar_path": null,
          "rating": 4, "body": "Отлично, но людно", "visited_on": "2026-09-27",
          "created_at": "2026-09-28T10:00:00Z", "edited_at": "2026-09-29T10:00:00Z",
          "is_own": null, "helpful_count": 3, "marked_helpful": true}]
        """
        let reviews = try decoder.decode([PlaceReview].self, from: Data(json.utf8))
        let review = try #require(reviews.first)
        #expect(review.rating == 4)
        #expect(review.visitedOn == CalendarDay(year: 2026, month: 9, day: 27))
        #expect(!review.isOwn, "у гостя null — не своё")
        #expect(review.helpful == ReactionState(count: 3, reacted: true))
        #expect(review.editedAt != nil)
        let cached = try decoder.decode(PlaceReview.self, from: {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(review)
        }())
        #expect(cached == review)

        let summary = try JSONDecoder().decode(ReviewSummary.self, from: Data("""
        {"reviews_count": 2, "rating_avg": 3.5, "stars": [0, 0, 1, 1, 0], "can_review": true,
         "my_review_id": "aaaaaaaa-0000-0000-0000-000000000001", "my_rating": 4, "my_body": null,
         "my_visited_on": "2026-09-27"}
        """.utf8))
        #expect(summary.ratingAverage == 3.5)
        #expect(summary.share(of: 4) == 0.5)
        #expect(summary.share(of: 5) == 0)
        #expect(summary.myReview?.rating == 4)

        let empty = try JSONDecoder().decode(ReviewSummary.self, from: Data("""
        {"reviews_count": 0, "rating_avg": null, "stars": [0, 0, 0, 0, 0], "can_review": false,
         "my_review_id": null, "my_rating": null, "my_body": null, "my_visited_on": null}
        """.utf8))
        #expect(empty.ratingAverage == nil)
        #expect(empty.myReview == nil)
        #expect(empty.share(of: 3) == 0)
    }

    @Test func reviewDraftValidation() {
        let place = UUID()
        var draft = ReviewDraft(placeID: place, today: CalendarDay(year: 2026, month: 9, day: 30))
        #expect(!draft.isValid, "без оценки")
        #expect(draft.visitedOn == CalendarDay(year: 2026, month: 9, day: 30))
        draft.rating = 5
        #expect(draft.isValid)
        draft.body = String(repeating: "а", count: 2001)
        #expect(!draft.isValid)

        let existing = MyReview(id: UUID(), rating: 3, body: "Нормально", visitedOn: CalendarDay(year: 2026, month: 9, day: 1))
        let editing = ReviewDraft(placeID: place, existing: existing)
        #expect(editing.rating == 3)
        #expect(editing.body == "Нормально")
        #expect(editing.visitedOn == CalendarDay(year: 2026, month: 9, day: 1))
    }

    @Test func decodesThreadsAndPosts() throws {
        let threads = try decoder.decode([ThreadSummary].self, from: Data("""
        [{"thread_id": "dddddddd-0000-0000-0000-000000000001", "author_id": "33333333-3333-3333-3333-333333333333",
          "author_username": "stranger", "author_display_name": null, "author_avatar_path": null,
          "title": "Как проехать после дождя?", "body_preview": "Кто был на этой неделе?",
          "posts_count": 2, "last_activity_at": "2026-09-30T10:00:00Z",
          "created_at": "2026-09-29T10:00:00Z", "is_own": false}]
        """.utf8))
        #expect(threads.first?.postsCount == 2)

        let posts = try decoder.decode([ThreadPost].self, from: Data("""
        [{"post_id": "eeeeeeee-0000-0000-0000-000000000002", "author_id": "22222222-2222-2222-2222-222222222222",
          "author_username": "friend", "author_display_name": "Друг", "author_avatar_path": null,
          "body": "Подтверждаю", "created_at": "2026-09-30T10:00:00Z", "edited_at": null, "is_own": true,
          "quote": {"post_id": "eeeeeeee-0000-0000-0000-000000000001", "author_username": "author",
                    "author_display_name": null, "body": "Вчера проехал на седане"},
          "reactions_count": 1, "reacted": false},
         {"post_id": "eeeeeeee-0000-0000-0000-000000000003", "author_id": "22222222-2222-2222-2222-222222222222",
          "author_username": "friend", "body": "Без цитаты", "created_at": "2026-09-30T11:00:00Z",
          "is_own": false, "quote": null, "reactions_count": 0, "reacted": false}]
        """.utf8))
        #expect(posts[0].quote?.authorUsername == "author")
        #expect(posts[0].reactions.count == 1)
        #expect(posts[1].quote == nil)

        let thread = try decoder.decode(ThreadDetails.self, from: Data("""
        {"thread_id": "dddddddd-0000-0000-0000-000000000001", "place_id": "aaaaaaaa-0000-0000-0000-000000000001",
         "place_name": "Публичное P", "author_id": "33333333-3333-3333-3333-333333333333",
         "author_username": "stranger", "title": "Как проехать?", "body": "Текст", "posts_count": 2,
         "last_activity_at": "2026-09-30T10:00:00Z", "created_at": "2026-09-29T10:00:00Z",
         "edited_at": null, "is_own": false}
        """.utf8))
        #expect(thread.placeName == "Публичное P")
    }

    @Test func threadAndPostDraftValidation() {
        var thread = ThreadDraft(placeID: UUID())
        thread.title = " Ок "
        thread.body = "Текст"
        #expect(!thread.isValid, "заголовок короче 3 символов")
        thread.title = "Где наживка?"
        #expect(thread.isValid)
        thread.body = "   "
        #expect(!thread.isValid)

        var post = PostDraft(threadID: UUID())
        #expect(!post.isValid)
        post.body = "  Спасибо  "
        #expect(post.isValid)
        #expect(post.trimmedBody == "Спасибо")
    }

    @Test func reactionsToggleAndDecode() throws {
        let state = ReactionState(count: 2, reacted: false)
        #expect(state.toggled() == ReactionState(count: 3, reacted: true))
        #expect(state.toggled().toggled() == state)
        #expect(ReactionState(count: 0, reacted: true).toggled() == ReactionState(count: 0, reacted: false))

        let rows = try JSONDecoder().decode([ReactionSummaryRow].self, from: Data("""
        [{"target_kind": "trip", "target_id": "77777777-0000-0000-0000-000000000001", "reactions_count": 1, "reacted": true}]
        """.utf8))
        #expect(rows.first?.key == ReactionKey(.trip, UUID(uuidString: "77777777-0000-0000-0000-000000000001")!))
        #expect(rows.first?.state == ReactionState(count: 1, reacted: true))
    }

    @Test func feedReviewAndReactionKeys() throws {
        let json = """
        [{"kind": "review", "id": "aaaaaaaa-0000-0000-0000-000000000009", "at": "2026-09-30T10:00:00Z",
          "author_id": "11111111-1111-1111-1111-111111111111", "author_username": "author",
          "data": {"place_id": "aaaaaaaa-0000-0000-0000-000000000001", "place_name": "Публичное P",
                   "place_type": "fishing_spot", "rating": 5, "body": null}},
         {"kind": "place", "id": "aaaaaaaa-0000-0000-0000-000000000005", "at": "2026-09-29T10:00:00Z",
          "author_id": "11111111-1111-1111-1111-111111111111",
          "data": {"place_type": "water_body", "name": "Новое", "approximate": false}}]
        """
        let items = try decoder.decode([FeedItem].self, from: Data(json.utf8))
        guard case .review(let review) = items[0].content else {
            Issue.record("ожидался отзыв")
            return
        }
        #expect(review.rating == 5)
        #expect(items[0].reactionKey == ReactionKey(.review, items[0].id))
        #expect(items[1].reactionKey == nil)
        let cached = try JSONDecoder().decode([FeedItem].self, from: JSONEncoder().encode(items))
        #expect(cached == items)
    }

    @Test func refusalCodes() {
        #expect(CommunityRefusal(rawValue: "DL001") == .checkinRequired)
        #expect(CommunityRefusal(rawValue: "DL003")?.messageKey == "community.error.tooOften")
        #expect(CommunityRefusal(rawValue: "42501") == nil)
    }
}
