import Backend
import DaladaCore
import DaladaUI
import DesignComponents
import DesignTokens
import Persistence
import SwiftUI
import Sync

/// Вкладка «Профиль»: шапка (нажатие — настройки профиля), статистика, очередь отправки, мои друзья,
/// уловы, места и поездки. Гостю — вход. Карточка сервера — только когда с ним проблема.
struct ProfileHomeView: View {
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @State private var connection: ConnectionState = .checking
    @State private var showsAbout = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    content
                    if connection.isProblem {
                        BackendStatusCard(state: connection)
                    }
                }
                .screenPadding()
                .padding(.bottom, AppSpacing.xl)
            }
            .navigationTitle("tab.profile")
            .navigationDestination(isPresented: $showsAbout) {
                AboutView()
            }
            .task { await checkConnection() }
            .toolbar {
                if session.profile == nil {
                    // Гостю — поддержка и документы.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsAbout = true
                        } label: {
                            Image(systemName: "info.circle")
                                .accessibilityLabel(Text("about.title"))
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
                NavigationLink {
                    ProfileSettingsView(environment: environment)
                } label: {
                    ProfileHeader(profile: profile)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("profile.settings.title"))
                ProfileStatsCard(environment: environment, userID: profile.id)
                PendingQueueSection()
                MyFriendsSection(environment: environment, userID: profile.id)
                MyCatchesSection(environment: environment, userID: profile.id)
                MyPlacesSection(environment: environment, userID: profile.id)
                MyTripsSection(environment: environment, userID: profile.id)
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

    private func checkConnection() async {
        guard let backend = environment.backend else {
            connection = .notConfigured
            return
        }
        connection = await backend.checkConnection()
    }

    private var historyPlaceholder: some View {
        PlaceholderScreen(
            icon: "figure.fishing",
            title: String(localized: "profile.empty.title"),
            description: String(localized: "profile.empty.description")
        )
    }
}

// MARK: - Разделы профиля

/// Раздел профиля: заголовок со значком, «Все» (если есть куда) и карточка с содержимым.
struct ProfileSection<Content: View, Destination: View>: View {
    let titleKey: String.LocalizationValue
    let systemImage: String
    let showsAll: Bool
    let destination: Destination
    let content: Content

    init(
        _ titleKey: String.LocalizationValue,
        systemImage: String,
        showsAll: Bool = true,
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder content: () -> Content
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.showsAll = showsAll
        self.destination = destination()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                SectionHeaderView(String(localized: titleKey), systemImage: systemImage)
                Spacer(minLength: 0)
                if showsAll {
                    NavigationLink {
                        destination
                    } label: {
                        Text("trips.all")
                            .font(AppTypography.bodySmall)
                    }
                }
            }
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardContentPadding()
            .cardStyle()
        }
    }
}

/// Подсказка в пустом разделе профиля.
private struct ProfileSectionHint: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(AppTypography.bodySmall)
            .foregroundStyle(AppColors.textSecondary)
    }
}

/// «Мои друзья»: запросы в друзья, лента аватаров (нажатие — профиль друга), «Все» — друзья и
/// поиск. Без друзей — подсказка и «Найти людей».
struct MyFriendsSection: View {
    let environment: AppEnvironment
    let userID: UUID

    @State private var friends: [Friend] = []
    @State private var incomingCount = 0
    @State private var isLoaded = false

    var body: some View {
        ProfileSection("profile.friends.title", systemImage: "person.2") {
            FriendsView(environment: environment)
        } content: {
            if incomingCount > 0 {
                NavigationLink {
                    FriendsView(environment: environment)
                } label: {
                    UniversalRow(config: .info, leadingIcon: .sfSymbol("person.badge.plus", color: AppColors.accent)) {
                        Text("friends.requests")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColors.textPrimary)
                    } trailing: {
                        BadgeView("\(incomingCount)", color: AppColors.destructive, style: .filled)
                        DisclosureChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !friends.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: AppSpacing.lg) {
                        ForEach(friends) { friend in
                            friendAvatar(friend)
                        }
                    }
                }
            } else if isLoaded {
                ProfileSectionHint(text: String(localized: "friends.empty"))
                NavigationLink {
                    FindPeopleView(environment: environment)
                } label: {
                    Label("friends.find", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .secondaryButton()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .task(id: userID) { await load() }
    }

    @ViewBuilder
    private func friendAvatar(_ friend: Friend) -> some View {
        let label = VStack(spacing: AppSpacing.xs) {
            PersonAvatar(name: friend.displayName ?? friend.username, path: friend.avatarPath, size: AppIconSize.xxxl)
            Text(verbatim: shortName(friend))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
        }
        .frame(width: AppIconSize.ultra)
        if let username = friend.username {
            NavigationLink {
                UserProfileView(username: username, environment: environment)
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    /// Имя под аватаром: первое слово имени или @username.
    private func shortName(_ friend: Friend) -> String {
        if let name = friend.displayName?.split(separator: " ").first {
            return String(name)
        }
        return friend.username.map { "@" + $0 } ?? String(localized: "profile.noName")
    }

    private func load() async {
        defer { isLoaded = true }
        guard let backend = environment.backend else { return }
        if let loaded = try? await backend.myFriends() {
            friends = loaded
        }
        if let requests = try? await backend.myFriendRequests() {
            incomingCount = requests.filter { $0.direction == .incoming }.count
        }
    }
}

/// «Мои уловы» (RPC `my_catches`): три последних в профиле, «Все» — полный список. Обновляется
/// после отправки очереди; без сети — сохранённый список.
struct MyCatchesSection: View {
    let environment: AppEnvironment
    let userID: UUID

    @Environment(SyncEngine.self) private var sync
    @State private var catches: [MyCatch] = []
    @State private var isLoaded = false

    var body: some View {
        ProfileSection("profile.catches.title", systemImage: "fish", showsAll: catches.count > 3) {
            MyCatchesView(environment: environment, userID: userID)
        } content: {
            if !catches.isEmpty {
                ForEach(catches.prefix(3)) { item in
                    MyCatchRow(item: item)
                }
            } else if isLoaded {
                ProfileSectionHint(text: String(localized: "profile.catches.empty"))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .task(id: userID) {
            catches = await MyCatchesLoader(environment: environment, userID: userID).load()
            isLoaded = true
        }
        .onChange(of: sync.sentCount) { _, _ in
            Task { catches = await MyCatchesLoader(environment: environment, userID: userID).load() }
        }
    }
}

/// Все свои уловы.
struct MyCatchesView: View {
    let environment: AppEnvironment
    let userID: UUID

    @State private var catches: [MyCatch] = []
    @State private var isLoaded = false

    var body: some View {
        Group {
            if catches.isEmpty && isLoaded {
                PlaceholderScreen(
                    icon: "fish",
                    title: String(localized: "profile.catches.title"),
                    description: String(localized: "profile.catches.empty")
                )
            } else {
                List(catches) { item in
                    MyCatchRow(item: item)
                }
            }
        }
        .navigationTitle("profile.catches.title")
        .task {
            catches = await MyCatchesLoader(environment: environment, userID: userID).load(limit: 200)
            isLoaded = true
        }
    }
}

/// Улов: вид, вес, длина, «отпущена», место и дата.
private struct MyCatchRow: View {
    let item: MyCatch

    @Environment(SpeciesStore.self) private var speciesStore

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
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
            // Картинка улова для Stories и Telegram.
            CatchShareCardButton(catchID: item.id)
        }
        .task { await speciesStore.loadIfNeeded() }
    }
}

/// Свои уловы: сеть, без неё — сохранённый список.
struct MyCatchesLoader {
    let environment: AppEnvironment
    let userID: UUID

    func load(limit: Int = 20) async -> [MyCatch] {
        let key = CacheKey.myCatches(userID)
        if let backend = environment.backend, let loaded = try? await backend.myCatches(limit: limit) {
            if limit <= 20 {
                try? await environment.cache.save(loaded, for: key)
            }
            return loaded
        }
        let saved = (try? await environment.cache.load([MyCatch].self, for: key)) ?? []
        return Array(saved.prefix(limit))
    }
}

/// «Мои места»: три последних в профиле, «Все» — полный список (свои места любой видимости,
/// включая места на проверке). Нажатие открывает карточку места.
struct MyPlacesSection: View {
    let environment: AppEnvironment
    let userID: UUID

    @Environment(SyncEngine.self) private var sync
    @State private var places: [PlaceSummary] = []
    @State private var isLoaded = false
    @State private var selected: PlaceSelection?

    var body: some View {
        ProfileSection("places.mine.title", systemImage: "mappin.and.ellipse", showsAll: places.count > 3) {
            MyPlacesView(environment: environment)
        } content: {
            if !places.isEmpty {
                ForEach(places.prefix(3)) { place in
                    Button {
                        selected = PlaceSelection(id: place.id)
                    } label: {
                        PlaceRow(place: place)
                    }
                    .buttonStyle(.plain)
                }
            } else if isLoaded {
                ProfileSectionHint(text: String(localized: "places.mine.empty.description"))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .task(id: userID) { await load() }
        .onChange(of: sync.sentCount) { _, _ in
            Task { await load() }
        }
        .sheet(item: $selected, onDismiss: { Task { await load() } }) { selection in
            PlaceCardView(placeID: selection.id, environment: environment)
                .presentationDetents([.medium, .large])
        }
    }

    private func load() async {
        defer { isLoaded = true }
        let key = CacheKey.myPlaces(userID)
        if let backend = environment.backend, let loaded = try? await backend.myPlaces() {
            places = loaded
            try? await environment.cache.save(loaded, for: key)
        } else if places.isEmpty, let saved = try? await environment.cache.load([PlaceSummary].self, for: key) {
            places = saved
        }
    }
}

/// Счётчики профиля: дни на природе, поездки, километры, уловы (RPC `my_stats`).
/// Без сети — сохранённые; обновляются после отправки очереди.
struct ProfileStatsCard: View {
    let environment: AppEnvironment
    let userID: UUID

    @Environment(SyncEngine.self) private var sync
    @State private var stats: UserStats?

    var body: some View {
        Group {
            if let stats {
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    counter(String(stats.daysOutdoors), titleKey: "stats.days")
                    counter(String(stats.tripsCount), titleKey: "stats.trips")
                    counter(
                        (Double(stats.distanceM) / 1000).formatted(.number.precision(.fractionLength(0))),
                        titleKey: "stats.km"
                    )
                    counter(String(stats.catchesCount), titleKey: "stats.catches")
                }
                .cardContentPadding()
                .cardStyle()
            }
        }
        .task(id: userID) { await load() }
        .onChange(of: sync.sentCount) { _, _ in
            Task { await load() }
        }
    }

    private func counter(_ value: String, titleKey: LocalizedStringKey) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Text(verbatim: value)
                .font(AppTypography.h4)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(titleKey)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        let key = CacheKey.stats(userID)
        if let backend = environment.backend, let loaded = try? await backend.myStats() {
            stats = loaded
            try? await environment.cache.save(loaded, for: key)
        } else if stats == nil {
            stats = try? await environment.cache.load(UserStats.self, for: key)
        }
    }
}

/// Шапка профиля: аватар, имя, @username, город; нажатие открывает настройки профиля.
struct ProfileHeader: View {
    let profile: UserProfile

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            PersonAvatar(name: profile.displayName ?? profile.username, path: profile.avatarPath, size: AppIconSize.mega)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(verbatim: profile.displayName ?? String(localized: "profile.noName"))
                    .font(AppTypography.h4)
                    .foregroundStyle(AppColors.textPrimary)
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
            DisclosureChevron()
        }
        .cardContentPadding()
        .cardStyle()
        .contentShape(Rectangle())
    }
}

extension ConnectionState {
    /// Сервер не настроен или недоступен — стоит показать пользователю.
    var isProblem: Bool {
        switch self {
        case .notConfigured, .failed: true
        case .checking, .connected: false
        }
    }
}

/// Карточка «Сервер: подключено / нет соединения / не настроен».
struct BackendStatusCard: View {
    let state: ConnectionState

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
        .environment(SyncEngine(outbox: AppEnvironment.preview.database.outbox, sender: UnavailableSender()))
}
