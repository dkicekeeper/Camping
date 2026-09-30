import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI
import UserNotifications

// MARK: - Согласие

/// Согласие с условиями, правилами сообщества и политикой конфиденциальности — после входа
/// (и когда документы существенно изменились). Без согласия можно только выйти.
struct ConsentView: View {
    @Environment(SessionStore.self) private var session
    @State private var accepts = false
    @State private var error: String?

    private var language: String { PackingFormat.language }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("consent.body")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Link(destination: LegalDocuments.terms(language: language)) {
                            Label("legal.terms", systemImage: "doc.text")
                        }
                        Link(destination: LegalDocuments.privacyPolicy(language: language)) {
                            Label("legal.privacy", systemImage: "lock.shield")
                        }
                    }
                    .font(AppTypography.bodyEmphasis)

                    Toggle(isOn: $accepts) {
                        Text("consent.checkbox")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .toggleStyle(.switch)

                    if let error {
                        Text(verbatim: error)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.destructive)
                    }

                    Button {
                        Task { error = await session.acceptTerms() }
                    } label: {
                        Text("consent.continue")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryButton(disabled: !accepts || session.isWorking)
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.xl)
            }
            .navigationTitle("consent.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("profile.signOut") {
                        Task { await session.signOut() }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Документы и поддержка

/// Ссылки на документы и поддержку, почта, версия приложения — в «Аккаунте» и «О приложении».
struct LegalLinksSection: View {
    private var language: String { PackingFormat.language }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        Section {
            Link(destination: LegalDocuments.support(language: language)) {
                Label("legal.support", systemImage: "questionmark.circle")
            }
            Link(destination: LegalDocuments.supportMailURL) {
                LabeledContent {
                    Text(verbatim: LegalDocuments.supportEmail)
                } label: {
                    Label("legal.contact", systemImage: "envelope")
                }
            }
            Link(destination: LegalDocuments.terms(language: language)) {
                Label("legal.terms", systemImage: "doc.text")
            }
            Link(destination: LegalDocuments.privacyPolicy(language: language)) {
                Label("legal.privacy", systemImage: "lock.shield")
            }
        } header: {
            Text("about.title")
        } footer: {
            Text("legal.version \(version)")
        }
    }
}

/// «О приложении» для гостя: поддержка и документы.
struct AboutView: View {
    var body: some View {
        List {
            LegalLinksSection()
        }
        .navigationTitle("about.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Уведомления

/// «Уведомления» в «Аккаунте»: включены ли, «Включить» или переход в Настройки.
struct NotificationsSection: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        Section {
            HStack {
                Label("notifications.title", systemImage: "bell")
                Spacer(minLength: 0)
                switch status {
                case .some(let current) where PushRegistrar.isAllowed(current):
                    Text("notifications.on")
                        .foregroundStyle(AppColors.textSecondary)
                case .some(.denied):
                    Button("notifications.openSettings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.borderless)
                case .some:
                    Button("notifications.enable") {
                        Task {
                            await PushRegistrar.shared.requestPermissionIfNeeded()
                            await refresh()
                        }
                    }
                    .buttonStyle(.borderless)
                case nil:
                    ProgressView()
                }
            }
        } footer: {
            Text("notifications.footer")
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refresh() }
            }
        }
    }

    private func refresh() async {
        status = await PackingReminders.authorizationStatus()
    }
}
