import AppFeature
import SwiftUI

@main
struct DaladaApp: App {
    private let environment: AppEnvironment

    init() {
        AppBootstrap.configure()
        environment = .live()
    }

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
    }
}
