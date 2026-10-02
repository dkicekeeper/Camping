import Foundation
import Testing
@testable import DaladaCore

@Suite("Comments")
struct CommentsTests {
    @Test func decodesComment() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let comments = try decoder.decode([PostComment].self, from: Data("""
        [{"id": "eeeeeeee-0000-0000-0000-000000000001", "author_id": "22222222-2222-2222-2222-222222222222",
          "author_username": "friend_f", "author_display_name": null,
          "author_avatar_path": "22222222-2222-2222-2222-222222222222/aaaaaaaa-1111-1111-1111-111111111111.jpg",
          "body": "Отличный улов!", "created_at": "2026-10-02T10:00:00Z", "edited_at": null, "can_delete": true}]
        """.utf8))
        #expect(comments.count == 1)
        #expect(comments[0].author.username == "friend_f")
        #expect(comments[0].author.avatarPath?.hasSuffix(".jpg") == true)
        #expect(comments[0].canDelete)
        #expect(comments[0].editedAt == nil)
    }

    @Test func draftValidation() {
        let key = ReactionKey(.trip, UUID())
        #expect(!CommentDraft(target: key, body: "   ").isValid)
        #expect(CommentDraft(target: key, body: "  Привет  ").trimmedBody == "Привет")
        #expect(!CommentDraft(target: key, body: String(repeating: "а", count: 1001)).isValid)
        #expect(CommentDraft.canComment(.checkin))
        #expect(!CommentDraft.canComment(.post))
    }

    @Test func tripAndCommentsLinks() throws {
        let tripID = UUID()
        #expect(TripLink.tripID(from: TripLink.url(tripID: tripID)) == tripID)
        #expect(TripLink.tripID(from: URL(string: "dalada://thread/\(tripID.uuidString)")!) == nil)

        let key = ReactionKey(.checkin, UUID())
        let url = try #require(CommentsLink.url(key))
        #expect(url.absoluteString.hasPrefix("dalada://comments/checkin/"))
        #expect(CommentsLink.key(from: url) == key)
        #expect(CommentsLink.url(ReactionKey(.post, UUID())) == nil)
        #expect(CommentsLink.key(from: URL(string: "dalada://comments/post/\(UUID().uuidString)")!) == nil)
        #expect(CommentsLink.key(from: URL(string: "dalada://comments/checkin")!) == nil)
    }

    @Test func profileReadsFriendPostsSetting() throws {
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data("""
        {"id": "11111111-1111-1111-1111-111111111111", "username": "a", "display_name": null,
         "avatar_path": null, "city": null, "language": "ru", "terms_version": 1, "notify_friend_posts": false}
        """.utf8))
        #expect(profile.notifyFriendPosts == false)
        let old = try JSONDecoder().decode(UserProfile.self, from: Data("""
        {"id": "11111111-1111-1111-1111-111111111111", "language": "ru"}
        """.utf8))
        #expect(old.notifyFriendPosts == nil)
    }
}
