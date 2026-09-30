import Foundation
import Testing
@testable import DaladaCore

@Suite("Документы")
struct LegalTests {
    @Test func pageLinksOpenTheRightLanguage() {
        #expect(LegalDocuments.privacyPolicy(language: "kk").absoluteString
                == "https://dkicekeeper.github.io/Dalada/privacy-policy.html#kk")
        #expect(LegalDocuments.terms(language: "en").absoluteString.hasSuffix("terms-of-use.html#en"))
        #expect(LegalDocuments.support(language: "de").absoluteString.hasSuffix("support.html#ru"), "незнакомый язык — русский")
        #expect(LegalDocuments.supportMailURL.absoluteString == "mailto:dakacom@gmail.com?subject=Dalada")
    }

    @Test func consentIsNeededUntilCurrentVersion() throws {
        var profile = UserProfile(id: UUID())
        #expect(profile.needsTermsConsent)
        profile.termsVersion = LegalDocuments.version
        #expect(!profile.needsTermsConsent)
        let decoded = try JSONDecoder().decode(
            UserProfile.self,
            from: Data(#"{"id": "11111111-1111-1111-1111-111111111111", "language": "ru", "terms_version": 1}"#.utf8)
        )
        #expect(decoded.termsVersion == 1)
        let old = try JSONDecoder().decode(
            UserProfile.self,
            from: Data(#"{"id": "11111111-1111-1111-1111-111111111111", "language": "kk"}"#.utf8)
        )
        #expect(old.termsVersion == nil, "сохранённый профиль старой версии разбирается")
    }
}
