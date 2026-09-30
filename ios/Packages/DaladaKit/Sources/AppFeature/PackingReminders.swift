import DaladaCore
import Foundation
import UserNotifications

/// Напоминания о сборах накануне поездки — локальные уведомления на этом телефоне.
enum PackingReminders {
    private static let prefix = "packing."

    /// Спрашивает разрешение (один раз); `true` — уведомления разрешены.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// Пересоздаёт напоминания по текущим сборам: у каждых несобранных — накануне поездки
    /// в выбранное время. Без разрешения на уведомления ничего не делает.
    static func update(_ checklists: [Checklist], now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }

        for checklist in checklists where !checklist.isComplete {
            guard let date = checklist.reminderDate(), date > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "packing.reminder.title \(checklist.title)")
            content.body = String(localized: "packing.reminder.body \(checklist.checkedCount) \(checklist.items.count)")
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let request = UNNotificationRequest(
                identifier: prefix + checklist.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            try? await center.add(request)
        }
    }
}
