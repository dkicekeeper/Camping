import DaladaCore
import DesignTokens
import SwiftUI

/// Уведомления (из настроек профиля): разрешение системы, виды уведомлений и «тихие часы».
/// Переключатели меняются сразу; если сервер не принял — возвращаются к сохранённым.
struct NotificationSettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var settings = NotificationSettings()
    @State private var error: String?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        List {
            NotificationsSection()

            if session.profile != nil {
                Section {
                    Toggle("notifications.kind.replies", isOn: binding(\.replies))
                    Toggle("notifications.kind.friendRequests", isOn: binding(\.friendRequests))
                    Toggle("notifications.kind.comments", isOn: binding(\.comments))
                    Toggle("notifications.kind.friendPosts", isOn: binding(\.friendPosts))
                } header: {
                    Text("notifications.section.people")
                } footer: {
                    Text("notifications.people.footer")
                }

                Section {
                    Toggle("notifications.kind.bans", isOn: binding(\.bans))
                    Toggle("notifications.kind.placeActivity", isOn: binding(\.placeActivity))
                } header: {
                    Text("notifications.section.places")
                } footer: {
                    Text("notifications.places.footer")
                }

                Section {
                    Toggle("notifications.quiet.toggle", isOn: quietBinding)
                    if settings.quietHours != nil {
                        Picker("notifications.quiet.from", selection: hourBinding(\.from)) {
                            hourOptions
                        }
                        Picker("notifications.quiet.to", selection: hourBinding(\.to)) {
                            hourOptions
                        }
                    }
                } footer: {
                    if let error {
                        Text(verbatim: error)
                            .foregroundStyle(AppColors.destructive)
                    } else if let quiet = settings.quietHours, quiet.from == quiet.to {
                        Text("notifications.quiet.same")
                    } else {
                        Text("notifications.quiet.footer")
                    }
                }
            }
        }
        .navigationTitle("notifications.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let saved = session.profile?.notificationSettings {
                settings = saved
            }
        }
    }

    private var hourOptions: some View {
        ForEach(0..<24, id: \.self) { hour in
            Text(verbatim: Self.hourLabel(hour)).tag(hour)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<NotificationSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { isOn in
                settings[keyPath: keyPath] = isOn
                save()
            }
        )
    }

    private var quietBinding: Binding<Bool> {
        Binding(
            get: { settings.quietHours != nil },
            set: { isOn in
                settings.quietHours = isOn ? .default : nil
                save()
            }
        )
    }

    private func hourBinding(_ keyPath: WritableKeyPath<QuietHours, Int>) -> Binding<Int> {
        Binding(
            get: { settings.quietHours?[keyPath: keyPath] ?? QuietHours.default[keyPath: keyPath] },
            set: { hour in
                settings.quietHours?[keyPath: keyPath] = hour
                save()
            }
        )
    }

    /// Частые изменения (колесо часов) склеиваются: уходит последнее состояние.
    private func save() {
        let wanted = settings
        error = nil
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            let failure = await session.updateNotificationSettings(wanted)
            if Task.isCancelled { return }
            error = failure
            if failure != nil, let saved = session.profile?.notificationSettings {
                settings = saved
            }
        }
    }

    /// «22:00» или «10 PM» — как принято в языке и настройках телефона.
    static func hourLabel(_ hour: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour)) ?? .now
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: .gmt))
    }
}
