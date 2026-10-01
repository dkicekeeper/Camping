import Backend
import CoreImage.CIFilterBuiltins
import DaladaCore
import DaladaUI
import DesignComponents
import DesignTokens
import SwiftUI

// MARK: - Общие части

/// Строка человека: аватар, имя, @username.
struct PersonRow<Trailing: View>: View {
    let displayName: String?
    let username: String?
    let trailing: Trailing

    init(displayName: String?, username: String?, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.displayName = displayName
        self.username = username
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            AvatarView(name: displayName ?? username)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: displayName ?? username.map { "@" + $0 } ?? String(localized: "profile.noName"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                if let username, displayName != nil {
                    Text(verbatim: "@" + username)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .contentShape(Rectangle())
    }
}

/// Ссылка-приглашение для открытия профиля: `.sheet(item:)`.
struct ProfileLink: Identifiable, Hashable {
    let username: String
    var id: String { username }
}

// MARK: - Друзья

/// Друзья: входящие запросы, список друзей, отправленные запросы, заблокированные.
struct FriendsView: View {
    let environment: AppEnvironment

    @State private var friends: [Friend] = []
    @State private var requests: [FriendRequest] = []
    @State private var isLoaded = false
    @State private var loadError: String?
    @State private var showsInvite = false

    private var backend: BackendClient? { environment.backend }
    private var incoming: [FriendRequest] { requests.filter { $0.direction == .incoming } }
    private var outgoing: [FriendRequest] { requests.filter { $0.direction == .outgoing } }

    var body: some View {
        List {
            if !incoming.isEmpty {
                Section("friends.requests") {
                    ForEach(incoming) { request in
                        PersonRow(displayName: request.displayName, username: request.username) {
                            HStack(spacing: AppSpacing.sm) {
                                Button("friends.accept") {
                                    Task { await respond(request, accept: true) }
                                }
                                .buttonStyle(.borderedProminent)
                                Button("friends.decline") {
                                    Task { await respond(request, accept: false) }
                                }
                                .buttonStyle(.bordered)
                            }
                            .font(AppTypography.bodySmall)
                        }
                    }
                }
            }

            Section("friends.title") {
                if friends.isEmpty && isLoaded {
                    Text(loadError ?? String(localized: "friends.empty"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                ForEach(friends) { friend in
                    NavigationLink {
                        if let username = friend.username {
                            UserProfileView(username: username, environment: environment)
                        }
                    } label: {
                        PersonRow(displayName: friend.displayName, username: friend.username)
                    }
                }
                NavigationLink {
                    FindPeopleView(environment: environment)
                } label: {
                    Label("friends.find", systemImage: "magnifyingglass")
                }
            }

            if !outgoing.isEmpty {
                Section("friends.outgoing") {
                    ForEach(outgoing) { request in
                        PersonRow(displayName: request.displayName, username: request.username) {
                            Button("friends.cancel") {
                                Task { await cancel(request) }
                            }
                            .buttonStyle(.bordered)
                            .font(AppTypography.bodySmall)
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    BlockedUsersView(environment: environment)
                } label: {
                    Label("friends.blocked", systemImage: "hand.raised")
                }
            }
        }
        .navigationTitle("friends.title")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("friends.invite", systemImage: "qrcode") {
                    showsInvite = true
                }
            }
        }
        .sheet(isPresented: $showsInvite) {
            InviteView()
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        defer { isLoaded = true }
        guard let backend else { return }
        do {
            async let loadedFriends = backend.myFriends()
            async let loadedRequests = backend.myFriendRequests()
            (friends, requests) = try await (loadedFriends, loadedRequests)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func respond(_ request: FriendRequest, accept: Bool) async {
        try? await backend?.respondToFriendRequest(request.id, accept: accept)
        await load()
    }

    private func cancel(_ request: FriendRequest) async {
        try? await backend?.cancelFriendRequest(request.id)
        await load()
    }
}

/// «Друзья» в профиле: число друзей и новых запросов.
struct FriendsEntryRow: View {
    let environment: AppEnvironment
    let userID: UUID

    @State private var friendsCount: Int?
    @State private var incomingCount = 0

    var body: some View {
        NavigationLink {
            FriendsView(environment: environment)
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "person.2")
                    .foregroundStyle(AppColors.accent)
                Text("friends.title")
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                if let friendsCount {
                    Text(verbatim: "\(friendsCount)")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: 0)
                if incomingCount > 0 {
                    BadgeView(
                        "\(incomingCount)",
                        systemImage: "person.badge.plus",
                        color: AppColors.destructive,
                        style: .filled
                    )
                    .accessibilityLabel(Text("friends.requests"))
                }
                DisclosureChevron()
            }
            .cardContentPadding()
            .cardStyle()
        }
        .buttonStyle(.plain)
        .task(id: userID) { await load() }
    }

    private func load() async {
        guard let backend = environment.backend else { return }
        if let friends = try? await backend.myFriends() {
            friendsCount = friends.count
        }
        if let requests = try? await backend.myFriendRequests() {
            incomingCount = requests.filter { $0.direction == .incoming }.count
        }
    }
}

// MARK: - Поиск

/// Найти людей по имени или @username.
struct FindPeopleView: View {
    let environment: AppEnvironment

    @State private var query = ""
    @State private var results: [PublicProfile] = []
    @State private var searched = false

    private var trimmed: String {
        query.trimmingCharacters(in: CharacterSet(charactersIn: "@ ").union(.whitespacesAndNewlines))
    }

    var body: some View {
        List {
            if trimmed.count < 2 {
                Text("friends.search.hint")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            } else if results.isEmpty && searched {
                Text("friends.search.empty")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
            ForEach(results) { profile in
                if let username = profile.username {
                    NavigationLink {
                        UserProfileView(username: username, environment: environment)
                    } label: {
                        PersonRow(displayName: profile.displayName, username: profile.username) {
                            RelationshipBadge(profile: profile)
                        }
                    }
                }
            }
        }
        .navigationTitle("friends.find")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("friends.search.prompt"))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .task(id: trimmed) { await search() }
    }

    private func search() async {
        searched = false
        guard trimmed.count >= 2, let backend = environment.backend else {
            results = []
            return
        }
        // Ищем, когда пользователь перестал печатать.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        results = (try? await backend.searchProfiles(trimmed)) ?? []
        searched = true
    }
}

/// Отношение к человеку в строке поиска: «Друзья», «Запрос отправлен», «Хочет дружить».
struct RelationshipBadge: View {
    let profile: PublicProfile

    var body: some View {
        if profile.isFriend {
            Label("person.friends", systemImage: "checkmark")
                .labelStyle(.iconOnly)
                .foregroundStyle(AppColors.success)
                .accessibilityLabel(Text("person.friends"))
        } else if profile.requestStatus == .outgoing {
            Text("person.requested")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        } else if profile.requestStatus == .incoming {
            Text("person.wantsToBeFriends")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.accent)
        }
    }
}

// MARK: - Профиль человека

/// Профиль другого человека: имя, @username, дружба, итоги, поездки и места, которые я вижу;
/// меню — удалить из друзей, заблокировать.
struct UserProfileView: View {
    let username: String
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @State private var profile: PublicProfile?
    @State private var isBlocked = false
    @State private var loadState: LoadState = .loading
    @State private var isWorking = false
    @State private var confirmsBlock = false
    @State private var confirmsRemove = false
    @State private var reports = false

    enum LoadState {
        case loading
        case loaded
        case notFound
        case failed(String)
    }

    private var backend: BackendClient? { environment.backend }

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notFound:
                EmptyStateView(
                    icon: "person.slash",
                    title: String(localized: "person.notFound"),
                    description: "@" + username
                )
            case .failed(let message):
                EmptyStateView(
                    icon: "wifi.slash",
                    title: String(localized: "person.failed"),
                    description: message,
                    actionTitle: String(localized: "common.retry"),
                    action: { Task { await load() } },
                    style: .error
                )
            case .loaded:
                if let profile {
                    content(profile)
                }
            }
        }
        .navigationTitle(Text(verbatim: "@" + username))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let profile, profile.id != session.profile?.id {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if profile.isFriend {
                            Button("person.removeFriend", systemImage: "person.badge.minus", role: .destructive) {
                                confirmsRemove = true
                            }
                        }
                        Button("moderation.report", systemImage: "flag") {
                            reports = true
                        }
                        Button("person.block", systemImage: "hand.raised", role: .destructive) {
                            confirmsBlock = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel(Text("profile.menu"))
                    }
                }
            }
        }
        .confirmationDialog("person.blockConfirm", isPresented: $confirmsBlock, titleVisibility: .visible) {
            Button("person.block", role: .destructive) {
                Task { await block() }
            }
        }
        .sheet(isPresented: $reports) {
            if let profile {
                ReportView(target: .user, targetID: profile.id)
                    .environment(session)
            }
        }
        .confirmationDialog("person.removeConfirm", isPresented: $confirmsRemove, titleVisibility: .visible) {
            Button("person.removeFriend", role: .destructive) {
                Task { await removeFriend() }
            }
        }
        .task { await load() }
    }

    private func content(_ profile: PublicProfile) -> some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                VStack(spacing: AppSpacing.lg) {
                    AvatarView(name: profile.displayName ?? profile.username, size: AppIconSize.mega)
                    VStack(spacing: AppSpacing.xs) {
                        Text(verbatim: profile.displayName ?? "@" + username)
                            .font(AppTypography.h3)
                        if profile.displayName != nil {
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
                    if profile.id != session.profile?.id {
                        relationshipButton(profile)
                    }
                }
                .frame(maxWidth: .infinity)

                UserContentSections(
                    userID: profile.id,
                    isFriend: profile.isFriend || profile.id == session.profile?.id,
                    environment: environment
                )
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.xl)
        }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func relationshipButton(_ profile: PublicProfile) -> some View {
        Group {
            if profile.isFriend {
                Label("person.friends", systemImage: "person.2.fill")
                    .foregroundStyle(AppColors.success)
                    .font(AppTypography.bodyEmphasis)
            } else if profile.requestStatus == .outgoing {
                Button {
                    Task { await cancelRequest(profile) }
                } label: {
                    Label("person.requestedCancel", systemImage: "clock")
                        .frame(maxWidth: .infinity)
                }
                .secondaryButton()
            } else {
                Button {
                    Task { await sendRequest(profile) }
                } label: {
                    Label(
                        LocalizedStringKey(profile.requestStatus == .incoming ? "person.accept" : "person.add"),
                        systemImage: "person.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .primaryButton()
            }
        }
        .disabled(isWorking)
    }

    private func load() async {
        guard let backend else {
            loadState = .failed(String(localized: "backend.status.notConfigured"))
            return
        }
        do {
            if let loaded = try await backend.profile(username: username) {
                profile = loaded
                loadState = .loaded
            } else {
                loadState = .notFound
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func sendRequest(_ profile: PublicProfile) async {
        guard let backend else { return }
        isWorking = true
        defer { isWorking = false }
        switch try? await backend.sendFriendRequest(to: profile.id) {
        case .sent?:
            self.profile = profile.with(isFriend: false, requestStatus: .outgoing)
            // Ответ на запрос придёт пушем — объясним и спросим разрешение.
            Task { await NotificationPrimer.shared.offer() }
        case .accepted?, .alreadyFriends?:
            self.profile = profile.with(isFriend: true, requestStatus: nil)
        case nil:
            await load()
        }
    }

    private func cancelRequest(_ profile: PublicProfile) async {
        guard let backend else { return }
        isWorking = true
        defer { isWorking = false }
        if let request = try? await backend.myFriendRequests().first(where: { $0.userID == profile.id && $0.direction == .outgoing }) {
            try? await backend.cancelFriendRequest(request.id)
        }
        self.profile = profile.with(isFriend: false, requestStatus: nil)
    }

    private func removeFriend() async {
        guard let backend, let profile else { return }
        try? await backend.removeFriend(profile.id)
        self.profile = profile.with(isFriend: false, requestStatus: nil)
    }

    private func block() async {
        guard let backend, let profile else { return }
        try? await backend.block(profile.id)
        // Заблокированный больше не находится — показываем «не найден».
        self.profile = nil
        loadState = .notFound
    }
}

// MARK: - Приглашение

/// QR-код и ссылка на свой профиль: друг наводит камеру — открывается Dalada.
struct InviteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.xl) {
                if let username = session.profile?.username, let url = InviteLink.url(username: username) {
                    if let qr = QRCode.image(for: url.absoluteString) {
                        Image(decorative: qr, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240)
                            .padding(AppSpacing.lg)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: AppRadius.xl))
                            .accessibilityLabel(Text("invite.qr"))
                    }
                    Text(verbatim: "@" + username)
                        .font(AppTypography.h3)
                    Text("invite.hint")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                    ShareLink(
                        item: url,
                        message: Text("invite.shareMessage \(username)")
                    ) {
                        Label("invite.share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryButton()
                } else {
                    Text("invite.needsUsername")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.xl)
            .navigationTitle("invite.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}

/// QR-код из строки (CoreImage).
enum QRCode {
    static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

// MARK: - Заблокированные

/// Заблокированные: разблокировать.
struct BlockedUsersView: View {
    let environment: AppEnvironment

    @State private var blocked: [BlockedUser] = []
    @State private var isLoaded = false

    var body: some View {
        List {
            if blocked.isEmpty && isLoaded {
                Text("friends.blocked.empty")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
            ForEach(blocked) { user in
                PersonRow(displayName: user.displayName, username: user.username) {
                    Button("person.unblock") {
                        Task {
                            try? await environment.backend?.unblock(user.id)
                            await load()
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(AppTypography.bodySmall)
                }
            }
        }
        .navigationTitle("friends.blocked")
        .task { await load() }
    }

    private func load() async {
        defer { isLoaded = true }
        blocked = (try? await environment.backend?.myBlocks()) ?? []
    }
}
