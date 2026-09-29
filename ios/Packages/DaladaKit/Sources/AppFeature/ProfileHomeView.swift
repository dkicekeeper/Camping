import Backend
import DaladaUI
import DesignTokens
import SwiftUI

/// Вкладка «Профиль» (главная). Пока — заглушка и статус соединения с сервером для беты.
struct ProfileHomeView: View {
    let environment: AppEnvironment

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    PlaceholderScreen(
                        icon: "figure.fishing",
                        title: String(localized: "profile.empty.title"),
                        description: String(localized: "profile.empty.description")
                    )
                    BackendStatusCard(backend: environment.backend)
                }
                .screenPadding()
            }
            .navigationTitle("tab.profile")
        }
    }
}

/// Карточка «Сервер: подключено / нет соединения / не настроен».
struct BackendStatusCard: View {
    let backend: BackendClient?

    @State private var state: ConnectionState = .checking

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("backend.status.title")
                    .font(AppTypography.bodyEmphasis)
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .cardContentPadding()
        .cardStyle()
        .task {
            guard let backend else {
                state = .notConfigured
                return
            }
            state = .checking
            state = await backend.checkConnection()
        }
    }

    private var message: String {
        switch state {
        case .notConfigured: String(localized: "backend.status.notConfigured")
        case .checking: String(localized: "backend.status.checking")
        case .connected: String(localized: "backend.status.connected")
        case .failed(let reason): String(localized: "backend.status.failed") + " — " + reason
        }
    }

    private var symbol: String {
        switch state {
        case .connected: "checkmark.circle.fill"
        case .checking: "arrow.triangle.2.circlepath"
        case .notConfigured, .failed: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .connected: AppColors.success
        case .checking: AppColors.textSecondary
        case .notConfigured, .failed: AppColors.warning
        }
    }
}

#Preview {
    ProfileHomeView(environment: .preview)
}
