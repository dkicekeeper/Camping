import Foundation
import Testing
@testable import DaladaCore

@Suite("UsernameRules")
struct UsernameRulesTests {
    @Test(arguments: ["arman", "arman.k", "fisher_77", "abc", String(repeating: "a", count: 30), "  Arman.K  "])
    func validUsernames(_ username: String) {
        #expect(UsernameRules.isValidFormat(username))
    }

    @Test(arguments: ["ab", String(repeating: "a", count: 31), ".arman", "arman.", "arm..an", "арман", "arman k", "arman-k", ""])
    func invalidUsernames(_ username: String) {
        #expect(!UsernameRules.isValidFormat(username))
    }

    @Test func normalizationMatchesDatabase() {
        #expect(UsernameRules.normalized("  Arman.K ") == "arman.k")
    }
}

@Suite("UserProfile")
struct UserProfileTests {
    @Test func decodesDatabaseRow() throws {
        let json = """
        {"id": "11111111-1111-1111-1111-111111111111", "username": "arman", "display_name": "Арман",
         "avatar_path": null, "city": "Алматы", "language": "kk",
         "created_at": "2026-09-29T17:00:00+00:00", "updated_at": "2026-09-29T17:00:00+00:00"}
        """
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        #expect(profile.username == "arman")
        #expect(profile.displayName == "Арман")
        #expect(profile.avatarPath == nil)
        #expect(profile.language == "kk")
    }
}

@Suite("SecureRandom")
struct SecureRandomTests {
    @Test func producesRequestedLengthAndDiffers() {
        let a = SecureRandom.string(length: 32)
        let b = SecureRandom.string(length: 32)
        #expect(a.count == 32)
        #expect(a != b)
    }
}
