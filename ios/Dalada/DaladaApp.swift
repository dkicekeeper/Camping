import AppFeature
import SwiftUI

@main
struct DaladaApp: App {
    /// Пуши: токен APNs, показ и переход по нажатию.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
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
