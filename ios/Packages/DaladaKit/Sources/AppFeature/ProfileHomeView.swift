import Backend
import DaladaCore
import DaladaUI
import DesignComponents
import DesignTokens
import SwiftUI

/// Вкладка «Профиль» (главная): вход для гостя, шапка профиля, статус сервера.
struct ProfileHomeView: View {
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    content
                    BackendStatusCard(backend: environment.backend)
                }
                .screenPadding()
            }
            .navigationTitle("tab.profile")
            .toolbar {
                if session.profile != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("profile.signOut", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                Task { await session.signOut() }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .accessibilityLabel(Text("profile.menu"))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .loading:
            ProgressView()
                .padding(AppSpacing.xxl)
        case .guest:
            SignInCard()
            historyPlaceholder
        case .needsUsername, .signedIn:
            if let profile = session.profile {
                ProfileHeader(profile: profile)
                MyCatchesSection(backend: environment.backend, userID: profile.id) {
                    historyPlaceholder
                }
            } else {
                historyPlaceholder
            }
        case .profileUnavailable(let message):
            EmptyStateView(
                icon: "wifi.slash",
                title: String(localized: "profile.unavailable"),
                description: message,
                actionTitle: String(localized: "common.retry"),
                action: { Task { await session.reloadProfile() } },
                style: .error
            )
        }
    }

    private var historyPlaceholder: some View {
        PlaceholderScreen(
            icon: "figure.fishing",
            title: String(localized: "profile.empty.title"),
            description: String(localized: "profile.empty.description")
        )
    }
}

/// «Мои уловы» (RPC `my_catches`): последние уловы с местом и датой. Пока уловов нет —
/// показывает `placeholder`. Обновляется при каждом возврате на вкладку.
struct MyCatchesSection<Placeholder: View>: View {
    let backend: BackendClient?
    let userID: UUID
    let placeholder: Placeholder

    @Environment(SpeciesStore.self) private var speciesStore
    @State private var catches: [MyCatch] = []
    @State private var isLoaded = false

    init(backend: BackendClient?, userID: UUID, @ViewBuilder placeholder: () -> Placeholder) {
        self.backend = backend
        self.userID = userID
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if catches.isEmpty {
                if isLoaded {
                    placeholder
                } else {
                    ProgressView()
                        .padding(AppSpacing.xl)
                }
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    SectionHeaderView(String(localized: "profile.catches.title"), systemImage: "fish")
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        ForEach(catches) { item in
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                CatchSummaryRow(
                                    speciesName: speciesStore.name(for: item.speciesID),
                                    count: item.count,
                                    weightGrams: item.weightGrams,
                                    lengthMillimeters: item.lengthMillimeters,
                                    released: item.released
                                )
                                HStack(spacing: AppSpacing.xs) {
                                    if let placeName = item.placeName {
                                        Text(verbatim: placeName)
                                        Text(verbatim: "·")
                                    }
                                    Text(item.at, format: .dateTime.day().month().year())
                                }
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                    .cardContentPadding()
                    .cardStyle()
                }
            }
        }
        .task(id: userID) { await load() }
        .task { await speciesStore.loadIfNeeded() }
    }

    private func load() async {
        defer { isLoaded = true }
        guard let backend else { return }
        if let loaded = try? await backend.myCatches(limit: 20) {
            catches = loaded
        }
    }
}

/// Шапка профиля: инициалы вместо аватара (фото — позже), имя, @username, город.
struct ProfileHeader: View {
    let profile: UserProfile

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            Circle()
                .fill(AppColors.accent.opacity(0.15))
                .frame(width: AppIconSize.mega, height: AppIconSize.mega)
                .overlay {
                    Text(verbatim: initials)
                        .font(AppTypography.h3)
                        .foregroundStyle(AppColors.accent)
                }
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(verbatim: profile.displayName ?? String(localized: "profile.noName"))
                    .font(AppTypography.h4)
                if let username = profile.username {
                    Text(verbatim: "@" + username)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                if let city = profile.city {
                    Text(verbatim: city)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .cardContentPadding()
        .cardStyle()
    }

    private var initials: String {
        let source = profile.displayName ?? profile.username ?? "?"
        return source.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
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
        .environment(SessionStore(backend: nil))
        .environment(SpeciesStore(backend: nil))
}
