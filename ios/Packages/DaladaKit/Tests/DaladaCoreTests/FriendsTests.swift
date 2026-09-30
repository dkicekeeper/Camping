import Foundation
import Testing
@testable import DaladaCore

@Suite("Friends")
struct FriendsTests {
    @Test func decodesSearchResults() throws {
        let json = """
        [{"id": "22222222-2222-2222-2222-222222222222", "username": "arman", "display_name": "Арман",
          "avatar_path": null, "is_friend": false, "request_status": "outgoing"},
         {"id": "33333333-3333-3333-3333-333333333333", "username": "arsen_c", "display_name": null,
          "avatar_path": null, "is_friend": true, "request_status": null}]
        """
        let profiles = try JSONDecoder().decode([PublicProfile].self, from: Data(json.utf8))
        #expect(profiles[0].requestStatus == .outgoing)
        #expect(!profiles[0].isFriend)
        #expect(profiles[1].isFriend)
        #expect(profiles[1].requestStatus == nil)
        #expect(profiles[1].city == nil)
    }

    @Test func unknownRequestStatusIsIgnored() throws {
        let json = #"{"id": "22222222-2222-2222-2222-222222222222", "username": "arman", "city": "Алматы", "is_friend": false, "request_status": "declined"}"#
        let profile = try JSONDecoder().decode(PublicProfile.self, from: Data(json.utf8))
        #expect(profile.requestStatus == nil)
        #expect(profile.city == "Алматы")
    }

    @Test func decodesRequests() throws {
        let json = """
        [{"request_id": "aaaaaaaa-0000-0000-0000-000000000001", "direction": "incoming",
          "user_id": "33333333-3333-3333-3333-333333333333", "username": "arsen_c", "display_name": "Арсен",
          "avatar_path": null, "created_at": "2026-09-30T10:00:00Z"}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let requests = try decoder.decode([FriendRequest].self, from: Data(json.utf8))
        #expect(requests.first?.direction == .incoming)
        #expect(requests.first?.username == "arsen_c")
    }

    @Test func requestResultValues() throws {
        let results = try JSONDecoder().decode([FriendRequestResult].self, from: Data(#"["sent", "accepted", "already_friends"]"#.utf8))
        #expect(results == [.sent, .accepted, .alreadyFriends])
    }

    @Test func inviteLinkRoundTrip() throws {
        let url = try #require(InviteLink.url(username: "arman_77"))
        #expect(url.absoluteString == "dalada://u/arman_77")
        #expect(InviteLink.username(from: url) == "arman_77")
        #expect(InviteLink.username(from: URL(string: "DALADA://U/Arman")!) == "arman")
    }

    @Test func otherLinksAreNotInvites() {
        #expect(InviteLink.username(from: URL(string: "dalada://auth-callback#access_token=x")!) == nil)
        #expect(InviteLink.username(from: URL(string: "dalada://u/")!) == nil)
        #expect(InviteLink.username(from: URL(string: "dalada://u/a")!) == nil)
        #expect(InviteLink.username(from: URL(string: "https://example.com/u/arman")!) == nil)
        #expect(InviteLink.url(username: "no spaces") == nil)
    }
}
