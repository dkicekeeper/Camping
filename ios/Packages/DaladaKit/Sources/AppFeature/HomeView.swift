import Backend
import DaladaCore
import DaladaUI
import DesignComponents
import DesignTokens
import Persistence
import SwiftUI
import Sync

/// Вкладка «Главная»: лента постов (RPC `home_feed`) — поездки, отчёты, новые места и отзывы друзей
/// и свои, свежие обсуждения публичных мест. Гостю — вход и обсуждения. Без сети — сохранённая
/// первая страница.
struct HomeView: View {
    let environment: AppEnvironment

    private static let pageSize = 20

    @Environment(SessionStore.self) private var session
    @Environment(SpeciesStore.self) private var speciesStore
    @Environment(ReactionStore.self) private var reactions
    @Environment(SyncEngine.self) private var sync
    @State private var items: [FeedItem] = []
    @State private var next: FeedCursor?
    @State private var photoURLs: [String: URL] = [:]
    @State private var isLoaded = false
    @State private var isLoadingMore = false
    @State private var loadError: String?
    @State private var selectedPlace: PlaceSelection?
    @State private var showsFindPeople = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.lg) {
                    if session.state == .guest {
                        SignInCard()
                    }
                    feed
                }
                .screenPadding()
                .padding(.bottom, AppSpacing.xl)
            }
            .navigationTitle("tab.home")
            .toolbar {
                if session.profile != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsFindPeople = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .accessibilityLabel(Text("friends.find"))
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    StartTripButton(isCompact: true)
                }
            }
            .navigationDestination(isPresented: $showsFindPeople) {
                FindPeopleView(environment: environment)
            }
            .refreshable { await reload() }
            // Лента своя у каждого аккаунта: перезагружаем при входе и выходе.
            .task(id: viewerKey) { await reload() }
            .task { await speciesStore.loadIfNeeded() }
            // Свой отчёт или поездка ушли на сервер — показываем их в ленте.
            .onChange(of: sync.sentCount) { _, _ in
                Task { await reload() }
            }
            .sheet(item: $selectedPlace) { selection in
                PlaceCardView(placeID: selection.id, environment: environment)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private var feed: some View {
        if items.isEmpty {
            if !isLoaded {
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { _ in SkeletonRow() }
                }
                .skeletonLoadingLabel()
            } else if let loadError {
                EmptyStateView(
                    icon: "wifi.slash",
                    title: String(localized: "feed.failed"),
                    description: loadError,
                    actionTitle: String(localized: "common.retry"),
                    action: { Task { await reload() } },
                    style: .error
                )
            } else if session.profile != nil {
                EmptyStateView(
                    icon: "house",
                    title: String(localized: "home.empty.title"),
                    description: String(localized: "home.empty.description"),
                    actionTitle: String(localized: "friends.find"),
                    action: { showsFindPeople = true }
                )
            } else {
                EmptyStateView(
                    icon: "bubble.left.and.bubble.right",
                    title: String(localized: "home.guest.empty")
                )
            }
        } else {
            if session.profile == nil {
                SectionHeaderView(String(localized: "threads.title"), systemImage: "bubble.left.and.bubble.right")
            }
            ForEach(items) { item in
                FeedPostCard(
                    item: item,
                    environment: environment,
                    photoURLs: photoURLs,
                    isOwn: item.author.id == session.profile?.id
                ) { placeID in
                    selectedPlace = PlaceSelection(id: placeID)
                }
                .onAppear {
                    if item.id == items.last?.id { Task { await loadMore() } }
                }
            }
            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Чья лента: `nil`, пока профиль загружается (не показываем гостевую ленту на мгновение).
    private var viewerKey: String? {
        switch session.state {
        case .loading: nil
        case .guest: "guest"
        case .needsUsername(let profile), .signedIn(let profile): profile.id.uuidString
        case .profileUnavailable: "unavailable"
        }
    }

    private func reload() async {
        guard viewerKey != nil else { return }
        let key = CacheKey.homeFeed(viewer: session.profile?.id)
        var failure: String?
        if let backend = environment.backend {
            do {
                let page = try await backend.homeFeed(limit: Self.pageSize)
                try? await environment.cache.save(page.items, for: key)
                apply(page.items, next: page.next, error: nil)
                await prepare(page.items)
                return
            } catch is CancellationError {
                return
            } catch {
                failure = error.localizedDescription
            }
        }
        let saved = (try? await environment.cache.load([FeedItem].self, for: key)) ?? []
        apply(saved, next: nil, error: saved.isEmpty ? failure : nil)
        await prepare(saved)
    }

    private func apply(_ loaded: [FeedItem], next cursor: FeedCursor?, error: String?) {
        items = loaded
        next = cursor
        loadError = error
        isLoaded = true
    }

    private func loadMore() async {
        guard let cursor = next, !isLoadingMore, let backend = environment.backend else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await backend.homeFeed(limit: Self.pageSize, after: cursor) else { return }
        let known = Set(items.map(\.id))
        let fresh = page.items.filter { !known.contains($0.id) }
        items += fresh
        next = page.next
        await prepare(fresh)
    }

    /// Реакции и подписанные ссылки на фото для новых постов.
    private func prepare(_ items: [FeedItem]) async {
        await reactions.load(items.compactMap(\.reactionKey))
        let paths = items.flatMap { item -> [String] in
            guard case .checkin(let checkin) = item.content else { return [] }
            return checkin.media.flatMap { [$0.thumbnailPath, $0.path] }
        }
        guard !paths.isEmpty, let backend = environment.backend,
              let urls = try? await backend.signedMediaURLs(paths: paths)
        else { return }
        photoURLs.merge(urls) { _, new in new }
    }
}

// MARK: - Пост

/// Пост ленты: автор и что сделал, содержание (фото, трек, улов, текст), «респект» или число
/// ответов. Поездка открывает страницу поездки, обсуждение — обсуждение, остальное — карточку места.
struct FeedPostCard: View {
    let item: FeedItem
    let environment: AppEnvironment
    var photoURLs: [String: URL] = [:]
    var isOwn = false
    let onPlaceTap: @MainActor (UUID) -> Void

    @Environment(SessionStore.self) private var session
    @Environment(SpeciesStore.self) private var speciesStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            header
            content
            footer
        }
        .cardContentPadding()
        .cardStyle()
    }

    // MARK: Шапка

    @ViewBuilder
    private var header: some View {
        // Профиль автора открывается только со входом: гостю профили недоступны.
        if !isOwn, session.profile != nil, let username = item.author.username {
            NavigationLink {
                UserProfileView(username: username, environment: environment)
            } label: {
                author
            }
            .buttonStyle(.plain)
        } else {
            author
        }
    }

    private var author: some View {
        HStack(spacing: AppSpacing.md) {
            AvatarView(name: item.author.displayName ?? item.author.username)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: authorName)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(verbatim: kindTitle + " · " + item.at.formatted(.relative(presentation: .named)))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var authorName: String {
        if isOwn { return String(localized: "report.you") }
        return item.author.displayName ?? item.author.username.map { "@" + $0 } ?? String(localized: "profile.noName")
    }

    /// «Рыбалка», «Отчёт», «Новое место», «Отзыв», «Обсуждение».
    private var kindTitle: String {
        switch item.content {
        case .trip(let trip): String(localized: String.LocalizationValue(trip.activity.titleKey))
        case .checkin: String(localized: "home.kind.checkin")
        case .place: String(localized: "feed.newPlace")
        case .review: String(localized: "feed.review")
        case .thread: String(localized: "home.kind.thread")
        case .unsupported: ""
        }
    }

    // MARK: Содержание

    @ViewBuilder
    private var content: some View {
        switch item.content {
        case .trip(let trip):
            NavigationLink {
                TripDetailView(tripID: item.id, environment: environment)
            } label: {
                tripContent(trip)
            }
            .buttonStyle(.plain)
        case .checkin(let checkin):
            checkinContent(checkin)
        case .place(let place):
            Button {
                onPlaceTap(item.id)
            } label: {
                placeTile(name: place.name, type: place.placeType)
            }
            .buttonStyle(.plain)
        case .review(let review):
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                RatingView(rating: Double(review.rating), size: 16)
                if let body = review.body, !body.isEmpty {
                    Text(verbatim: body)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                }
                placeButton(id: review.placeID, name: review.placeName, type: review.placeType)
            }
        case .thread(let thread):
            NavigationLink {
                ThreadView(threadID: item.id, environment: environment)
            } label: {
                threadContent(thread)
            }
            .buttonStyle(.plain)
        case .unsupported:
            EmptyView()
        }
    }

    private func tripContent(_ trip: FeedTrip) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(verbatim: trip.title)
                .font(AppTypography.h4)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.leading)
            if let note = trip.note, !note.isEmpty {
                Text(verbatim: note)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            HStack(alignment: .top, spacing: AppSpacing.md) {
                StatTile(title: String(localized: "trip.stat.distance"), value: TripFormat.distance(Double(trip.distanceM)))
                StatTile(title: String(localized: "trip.stat.time"), value: TripFormat.duration(Double(trip.movingSeconds)))
                if trip.elevationGainM > 0 {
                    StatTile(title: String(localized: "trip.stat.elevation"), value: TripFormat.elevation(Double(trip.elevationGainM)))
                }
            }
            if !trip.segments.isEmpty {
                TrackPreviewView(segments: trip.segments)
            }
        }
        .contentShape(Rectangle())
    }

    private func checkinContent(_ checkin: FeedCheckin) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if !checkin.media.isEmpty {
                PostPhotoCarousel(media: checkin.media, urls: photoURLs)
            }
            if let note = checkin.note, !note.isEmpty {
                Text(verbatim: note)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
            }
            if !checkin.catches.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(checkin.catches) { item in
                        CatchSummaryRow(
                            speciesName: speciesStore.name(for: item.speciesID),
                            count: item.count,
                            weightGrams: item.weightGrams,
                            lengthMillimeters: item.lengthMillimeters,
                            released: item.released
                        )
                    }
                }
            }
            if let conditions = ConditionsText.make(checkin.conditions) {
                Text(verbatim: conditions)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            placeButton(id: checkin.placeID, name: checkin.placeName, type: checkin.placeType, verified: checkin.verified)
        }
    }

    private func threadContent(_ thread: FeedThread) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label {
                Text(verbatim: thread.placeName)
                    .lineLimit(1)
            } icon: {
                Image(systemName: thread.placeType.systemImage)
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
            Text(verbatim: thread.title)
                .font(AppTypography.h4)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.leading)
            if !thread.body.isEmpty {
                Text(verbatim: thread.body)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Новое место: значок типа, название и тип — нажатие открывает карточку.
    private func placeTile(name: String, type: PlaceType) -> some View {
        UniversalRow(config: .info, leadingIcon: .sfSymbol(type.systemImage, color: AppColors.accent, size: AppIconSize.xl)) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: name)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                Text(LocalizedStringKey(type.titleKey))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        } trailing: {
            DisclosureChevron()
        }
        .contentShape(Rectangle())
    }

    /// Место поста одной строкой: значок, название, «подтверждено».
    private func placeButton(id: UUID, name: String, type: PlaceType, verified: Bool = false) -> some View {
        Button {
            onPlaceTap(id)
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Label {
                    Text(verbatim: name)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: type.systemImage)
                        .foregroundStyle(AppColors.accent)
                }
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textPrimary)
                if verified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppColors.success)
                        .accessibilityLabel(Text("report.verified"))
                }
                Spacer(minLength: 0)
                DisclosureChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Подвал

    @ViewBuilder
    private var footer: some View {
        if let key = item.reactionKey {
            ReactionButton(key: key, isOwn: isOwn)
        } else if case .thread(let thread) = item.content {
            Label {
                Text("home.replies \(thread.postsCount)")
            } icon: {
                Image(systemName: "bubble.left")
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
        }
    }
}

// MARK: - Фото и трек в посте

/// Фото поста: листаются свайпом, нажатие открывает на весь экран.
struct PostPhotoCarousel: View {
    let media: [ReportMedia]
    let urls: [String: URL]

    @State private var opened: ReportMedia?

    var body: some View {
        TabView {
            ForEach(media) { item in
                Button {
                    opened = item
                } label: {
                    Color.clear
                        .overlay {
                            RemotePhoto(path: item.path, url: urls[item.path], placeholderPath: item.thumbnailPath)
                        }
                        .clipped()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("photo.open"))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: media.count > 1 ? .automatic : .never))
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .background(AppColors.bgMuted)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .fullScreenCover(item: $opened) { item in
            PhotoViewer(media: media, urls: urls, selection: item.id)
        }
    }
}

/// Превью маршрута в посте: линия трека без карты, север сверху, пропорции как на местности.
struct TrackPreviewView: View {
    let segments: [[GeoPoint]]

    var body: some View {
        let lines = TrackPreview.normalized(segments)
        let color = AppColors.accent
        Canvas { context, size in
            let points = lines.flatMap { $0 }
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
                  let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
            else { return }
            let inset: CGFloat = 20
            let width = CGFloat(max(maxX - minX, 0.000_001))
            let height = CGFloat(max(maxY - minY, 0.000_001))
            let scale = min((size.width - inset * 2) / width, (size.height - inset * 2) / height)
            let offsetX = (size.width - width * scale) / 2
            let offsetY = (size.height - height * scale) / 2
            func position(_ point: TrackPreview.Point) -> CGPoint {
                CGPoint(x: offsetX + CGFloat(point.x - minX) * scale, y: offsetY + CGFloat(point.y - minY) * scale)
            }
            var path = Path()
            for line in lines {
                guard let first = line.first else { continue }
                path.move(to: position(first))
                for point in line.dropFirst() {
                    path.addLine(to: position(point))
                }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(AppColors.bgMuted, in: RoundedRectangle(cornerRadius: AppRadius.md))
        .accessibilityHidden(true)
    }
}
