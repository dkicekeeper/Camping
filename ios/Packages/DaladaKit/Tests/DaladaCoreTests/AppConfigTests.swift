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

    @Test func mapStyleDefaultsToOpenFreeMap() {
        let config = AppConfig(info: [:])
        #expect(config.mapStyleURL == AppConfig.defaultMapStyleURL)
    }
}
