import DesignComponents
import DesignTokens
import Foundation
import SwiftUI
import UIKit

/// Перед системным запросом уведомлений — наше объяснение, в момент первой пользы (первый чекин,
/// сохранённое место, запрос в друзья, обсуждение). «Не сейчас» — не спрашиваем неделю.
/// Сам лист — `PermissionPrimerView` из DesignKit (общий с Tenra), тексты `push.primer.*`.
///
/// Лист показывается поверх самого верхнего экрана (UIKit): вызвать можно откуда угодно, даже из
/// листа поверх листа — SwiftUI из корня так не умеет.
@MainActor
final class NotificationPrimer {
    static let shared = NotificationPrimer()

    private weak var presented: UIViewController?

    private static let snoozeKey = "push.primer.snoozedUntil"
    private static let snooze: TimeInterval = 7 * 24 * 60 * 60

    /// Предложить включить уведомления, если система ещё не спрашивала и человек не отложил.
    func offer() async {
        guard presented == nil,
              await PackingReminders.authorizationStatus() == .notDetermined,
              Date().timeIntervalSince1970 >= UserDefaults.standard.double(forKey: Self.snoozeKey)
        else { return }
        // Даём закрыться листу, из которого пришли (форма чекина и т. п.).
        try? await Task.sleep(for: .milliseconds(700))
        guard presented == nil, let top = Self.topViewController() else { return }
        let host = UIHostingController(rootView: PermissionPrimerView(
            systemImage: "bell.badge",
            title: String(localized: "push.primer.title"),
            message: String(localized: "push.primer.body"),
            allowTitle: String(localized: "push.primer.allow"),
            laterTitle: String(localized: "push.primer.later"),
            onAllow: { [weak self] in await MainActor.run { self?.allow() } },
            onLater: { [weak self] in self?.later() }
        ))
        host.isModalInPresentation = true
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = false
        }
        presented = host
        top.present(host, animated: true)
    }

    private func allow() {
        close()
        Task { await PushRegistrar.shared.requestPermissionIfNeeded() }
    }

    private func later() {
        UserDefaults.standard.set(Date().timeIntervalSince1970 + Self.snooze, forKey: Self.snoozeKey)
        close()
    }

    private func close() {
        presented?.dismiss(animated: true)
        presented = nil
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow
            ?? scenes.first?.keyWindow,
            var top = window.rootViewController
        else { return nil }
        while let next = top.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }
}
