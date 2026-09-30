import AppFeature
import SwiftUI

@main
struct DaladaApp: App {
    /// Пуши: токен APNs, показ и переход по нажатию.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    private let environment: AppEnvironment
    /// Офлайн-очередь: общая для экранов и отправки в фоне.
    private let background: BackgroundSync

    init() {
        AppBootstrap.configure()
        environment = .live()
        background = BackgroundSync(environment: environment)
    }

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment, background: background)
        }
        // Система будит приложение, пока в очереди что-то ждёт отправки.
        .backgroundTask(.appRefresh(BackgroundSync.refreshTaskID)) { [background = self.background] in
            await background.runRefresh()
        }
    }
}
