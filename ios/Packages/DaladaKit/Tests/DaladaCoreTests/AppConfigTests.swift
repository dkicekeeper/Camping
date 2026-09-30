import Foundation
import Testing
@testable import DaladaCore

@Suite("AppConfig")
struct AppConfigTests {
    @Test func cloudHostUsesHTTPS() {
        let config = AppConfig(info: ["SupabaseHost": "abcd.supabase.co", "SupabaseKey": "sb_publishable_x"])
        #expect(config.supabaseURL?.absoluteString == "https://abcd.supabase.co")
        #expect(config.supabaseKey == "sb_publishable_x")
        #expect(config.isBackendConfigured)
    }

    @Test func localHostUsesHTTP() {
        let config = AppConfig(info: ["SupabaseHost": "127.0.0.1:54321", "SupabaseKey": "key"])
        #expect(config.supabaseURL?.absoluteString == "http://127.0.0.1:54321")
    }

    @Test(arguments: ["", "   ", "$(SUPABASE_HOST)"])
    func missingOrUnresolvedValuesMeanNotConfigured(host: String) {
        let config = AppConfig(info: ["SupabaseHost": host, "SupabaseKey": "key"])
        #expect(config.supabaseURL == nil)
        #expect(!config.isBackendConfigured)
    }

    @Test func mapStyleComesFromOwnBucketInTheInterfaceLanguage() {
        let config = AppConfig(info: [:])
        #expect(config.mapBaseURL == AppConfig.defaultMapBaseURL)
        #expect(config.mapStyleURL(language: "kk").absoluteString
            == "https://pub-06c03b3c9f2e4de7b1a196206e04c258.r2.dev/styles/liberty.kk.json")
        #expect(config.mapStyleURL(language: "en").lastPathComponent == "liberty.en.json")
        #expect(config.mapStyleURL(language: "de").lastPathComponent == "liberty.ru.json")
    }
}
