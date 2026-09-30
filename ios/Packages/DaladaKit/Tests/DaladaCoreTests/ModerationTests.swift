import Testing
@testable import DaladaCore

@Suite("Модерация")
struct ModerationTests {
    @Test func reasonsDependOnTarget() {
        #expect(ReportReason.options(for: .review) == ReportReason.allCases)
        #expect(!ReportReason.options(for: .user).contains(.privatePlace), "у человека нет «чужого места»")
        #expect(ReportReason.privatePlace.rawValue == "private_place")
        #expect(ReportReason.falseInfo.titleKey == "moderation.reason.false_info")
    }

    @Test func badWordsRefusal() {
        #expect(CommunityRefusal(rawValue: "DL005") == .badWords)
        #expect(CommunityRefusal.badWords.messageKey == "moderation.error.badWords")
    }
}
