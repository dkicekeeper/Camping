import Foundation
import Testing
@testable import DaladaCore

@Suite("Пуши")
struct PushTests {
    @Test func tokenIsLowercaseHex() {
        #expect(PushToken.hex(Data([0x00, 0xAB, 0x0F, 0xFF])) == "00ab0fff")
    }

    @Test func threadLinkRoundTrips() throws {
        let id = try #require(UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000001"))
        let url = ThreadLink.url(threadID: id)
        #expect(url.absoluteString == "dalada://thread/dddddddd-0000-0000-0000-000000000001")
        #expect(ThreadLink.threadID(from: url) == id)
        #expect(ThreadLink.threadID(from: URL(string: "dalada://u/bob")!) == nil)
        #expect(ThreadLink.threadID(from: URL(string: "dalada://thread/not-a-uuid")!) == nil)
        #expect(InviteLink.username(from: url) == nil, "ссылка на обсуждение — не приглашение")
    }
}
