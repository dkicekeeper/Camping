import Backend
import DaladaCore
import Foundation
import UIKit
import UserNotifications

/// Пуш-уведомления на этом телефоне: регистрирует токен APNs для вошедшего аккаунта, спрашивает
/// разрешение в подходящий момент и убирает телефон из аккаунта при выходе.
@MainActor
final class PushRegistrar {
    static let shared = PushRegistrar()

    private var backend: BackendClient?
    private var userID: UUID?
    private var token: String?
    /// Что уже отправлено на сервер — чтобы не повторять при каждом возврате в приложение.
    private var uploadedToken: String?
    private var uploadedUser: UUID?

    static var environment: PushEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }

    /// Запуск, вход, выход, возврат в приложение: если уведомления разрешены — получить токен.
    func update(userID: UUID?, backend: BackendClient?) async {
        self.backend = backend
        self.userID = userID
        guard userID != nil else { return }
        if Self.isAllowed(await PackingReminders.authorizationStatus()) {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Токен от APNs (из `PushAppDelegate`).
    func didRegister(deviceToken: Data) {
        token = PushToken.hex(deviceToken)
        Task { await upload() }
    }

    /// Спросить разрешение после первого запроса в друзья, обсуждения или ответа — один раз.
    func requestPermissionIfNeeded() async {
        guard await PackingReminders.authorizationStatus() == .notDetermined else { return }
        if await PackingReminders.requestPermission() {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Перед выходом из аккаунта: этот телефон больше не получает его уведомления.
    func unregister() async {
        guard let backend, let token else { return }
        try? await backend.unregisterDevice(token: token)
        uploadedToken = nil
        uploadedUser = nil
    }

    private func upload() async {
        guard let backend, let userID, let token, backend.currentUserID == userID else { return }
        if uploadedToken == token && uploadedUser == userID { return }
        do {
            try await backend.registerDevice(token: token, environment: Self.environment, language: PackingFormat.language)
            uploadedToken = token
            uploadedUser = userID
        } catch {
            // Нет сети — отправим при следующем возврате в приложение.
        }
    }

    static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        case .notDetermined, .denied: false
        @unknown default: false
        }
    }
}

/// Делегат приложения для пушей: токен APNs, показ уведомлений, когда приложение открыто, и переход
/// по нажатию (ссылка `url` в уведомлении — на обсуждение или профиль).
public final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    override public init() {
        super.init()
    }

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrar.shared.didRegister(deviceToken: deviceToken)
    }

    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Симулятор или нет сети — попробуем при следующем запуске.
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let link = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: link)
        else { return }
        await MainActor.run {
            UIApplication.shared.open(url)
        }
    }
}
