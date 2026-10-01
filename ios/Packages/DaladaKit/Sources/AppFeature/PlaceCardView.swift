import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import Persistence
import SwiftUI
import Sync

/// Карточка места (RPC `place_card`): тип, название, видимость, описание, автор, маршрут,
/// «Я здесь», свежие отчёты (RPC `place_reports`) с «респектом», а у публичных мест — отзывы и
/// обсуждения. Без сети — сохранённая карточка и отчёты,
/// а свои чекины из очереди — с пометкой «Ожидает отправки».
struct PlaceCardView: View {
    let placeID: UUID
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @Environment(SpeciesStore.self) private var speciesStore
    @Environment(SyncEngine.self) private var sync
    @Environment(ReactionStore.self) private var reactions
    @Environment(RulesStore.self) private var rules
    @State private var state: LoadState = .loading
    @State private var reports: [PlaceReport] = []
    /// Подписанные ссылки на фото отчётов: путь в хранилище → ссылка (действует час).
    @State private var photoURLs: [String: URL] = [:]
    @State private var showsCheckin = false
    /// Показана сохранённая копия — сервер недоступен.
    @State private var isShowingSavedCopy = false

    private var backend: BackendClient? { environment.backend }
    private var cache: CacheStore { environment.cache }
    private var viewerID: UUID? { session.profile?.id }

    enum LoadState {
        case loading
        case loaded(PlaceDetails)
        case notFound
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loaded(let place):
                    content(place)
                case .notFound:
                    EmptyStateView(
                        icon: "mappin.slash",
                        title: String(localized: "place.card.notFound.title"),
                        description: String(localized: "place.card.notFound.description")
                    )
                case .failed(let message):
                    EmptyStateView(
                        icon: "wifi.slash",
                        title: String(localized: "place.card.failed"),
                        description: message,
                        actionTitle: String(localized: "common.retry"),
                        action: { Task { await load() } },
                        style: .error
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Сохранить место (закладка) — после входа.
                if case .loaded(let place) = state, session.profile != nil, !place.isOwn {
                    ToolbarItem(placement: .topBarTrailing) {
                        SavePlaceButton(placeID: place.id, environment: environment)
                    }
                }
                // Чужое место: пожаловаться или заблокировать автора (место тогда пропадёт).
                // Редакцию не блокируют — только жалоба.
                if case .loaded(let place) = state, !place.isOwn {
                    ToolbarItem(placement: .topBarTrailing) {
                        ModerationMenu(
                            target: .place,
                            targetID: place.id,
                            author: place.isEditorial
                                ? nil
                                : FeedAuthor(id: place.ownerID, username: place.ownerUsername, displayName: nil),
                            isToolbar: true
                        ) {
                            Task { await load() }
                        }
                    }
                }
            }
        }
        .task { await load() }
        .task { await speciesStore.loadIfNeeded() }
        // Чекин из очереди принят сервером — он появится среди обычных отчётов.
        .onChange(of: sync.sentCount) { _, _ in
            Task { await loadReports() }
        }
        .sheet(isPresented: $showsCheckin) {
            if case .loaded(let place) = state {
                CheckinFormView(placeID: place.id, placeName: place.name, coordinate: place.coordinate) {}
                    .environment(speciesStore)
                    .environment(sync)
                    .environment(rules)
            }
        }
    }

    private func content(_ place: PlaceDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Label(LocalizedStringKey(place.type.titleKey), systemImage: place.type.systemImage)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                    Text(verbatim: place.name)
                        .font(AppTypography.h3)
                }

                HStack(spacing: AppSpacing.sm) {
                    Label(LocalizedStringKey(place.visibility.titleKey), systemImage: place.visibility.systemImage)
                    if place.status == .pending {
                        Label("place.status.pending", systemImage: "hourglass")
                            .foregroundStyle(AppColors.warning)
                    }
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)

                if isShowingSavedCopy {
                    Label("offline.savedCopy", systemImage: "icloud.slash")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                if place.isApproximate {
                    RecommendationBox(
                        text: String(localized: "place.card.approximate"),
                        color: AppColors.accent,
                        icon: "circle.dashed"
                    )
                }

                if let description = place.description {
                    Text(verbatim: description)
                        .font(AppTypography.body)
                }

                if place.isEditorial {
                    Label("place.card.editorial", systemImage: "checkmark.seal")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                } else if let username = place.ownerUsername, !place.isOwn {
                    Text(verbatim: "@" + username)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                if place.source == .osm {
                    Text("place.card.osm")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }

                HStack(spacing: AppSpacing.md) {
                    if session.profile != nil {
                        Button {
                            showsCheckin = true
                        } label: {
                            Label("place.card.checkin", systemImage: "mappin.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .primaryButton()
                    }
                    if let destination = routeDestination(place) {
                        RouteButton(destination: destination)
                    }
                }

                // Запреты и промысловая мера в этой точке (работает без сети).
                PlaceRulesSection(coordinate: place.coordinate, environment: environment)

                reportsSection

                // Отзывы и обсуждения — только у публичных опубликованных мест.
                if place.visibility == .public && place.status == .published && !isShowingSavedCopy {
                    PlaceReviewsSection(place: place, environment: environment)
                    PlaceThreadsSection(place: place, environment: environment)
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
        }
    }

    @ViewBuilder
    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeaderView(String(localized: "place.card.reports"), systemImage: "clock")
            ForEach(pendingHere) { item in
                PendingReportRow(item: item)
            }
            if reports.isEmpty && pendingHere.isEmpty {
                Text("place.card.reports.empty")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                ForEach(reports) { report in
                    ReportRow(report: report, photoURLs: photoURLs) { blocked in
                        reports.removeAll { $0.authorID == blocked }
                    }
                }
            }
        }
    }

    /// Свои чекины в этом месте, ещё не принятые сервером.
    private var pendingHere: [PendingCheckin] {
        sync.pending.filter { $0.placeID == placeID }
    }

    /// Куда строить маршрут: точка подъезда, иначе само место. Для огрублённого места без точки
    /// подъезда маршрут не строим — иначе раскрыли бы примерную точку как точную.
    private func routeDestination(_ place: PlaceDetails) -> GeoPoint? {
        if let access = place.accessPoint { return access }
        return place.isApproximate ? nil : place.coordinate
    }

    private func load() async {
        guard let backend else {
            state = .failed(String(localized: "backend.status.notConfigured"))
            return
        }
        state = .loading
        let key = CacheKey.place(placeID, viewer: viewerID)
        do {
            if let place = try await backend.placeDetails(id: placeID) {
                state = .loaded(place)
                isShowingSavedCopy = false
                try? await cache.save(place, for: key)
                await loadReports()
            } else {
                state = .notFound
            }
        } catch {
            // Нет сети — показываем сохранённую карточку: из неё можно отметиться.
            if let saved = try? await cache.load(PlaceDetails.self, for: key) {
                state = .loaded(saved)
                isShowingSavedCopy = true
                reports = (try? await cache.load([PlaceReport].self, for: .reports(placeID, viewer: viewerID))) ?? []
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func loadReports() async {
        guard let backend,
              let loaded = try? await backend.placeReports(placeID: placeID)
        else { return }
        let paths = loaded.flatMap { report in report.media.flatMap { [$0.thumbnailPath, $0.path] } }
        let urls = (try? await backend.signedMediaURLs(paths: paths)) ?? [:]
        photoURLs = urls
        reports = loaded
        await reactions.load(loaded.map { ReactionKey(.checkin, $0.id) })
        try? await cache.save(loaded, for: .reports(placeID, viewer: viewerID))
    }
}

/// Отчёт в карточке места: автор, время, подтверждение, условия, заметка, уловы, фото.
struct ReportRow: View {
    let report: PlaceReport
    let photoURLs: [String: URL]
    /// Автора заблокировали — убрать его отчёты с экрана.
    var onBlocked: (@MainActor (UUID) -> Void)?

    @Environment(SpeciesStore.self) private var speciesStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                Text(verbatim: author)
                    .font(AppTypography.bodyEmphasis)
                if report.verified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppColors.success)
                        .accessibilityLabel(Text("report.verified"))
                }
                Spacer(minLength: 0)
                Text(report.at, style: .relative)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                if !report.isOwn {
                    ModerationMenu(
                        target: .checkin,
                        targetID: report.id,
                        author: FeedAuthor(id: report.authorID, username: report.authorUsername, displayName: report.authorDisplayName)
                    ) {
                        onBlocked?(report.authorID)
                    }
                }
            }

            if let conditionsText {
                Text(verbatim: conditionsText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            if let note = report.note {
                Text(verbatim: note)
                    .font(AppTypography.bodySmall)
            }

            ForEach(report.catches) { item in
                CatchSummaryRow(
                    speciesName: speciesStore.name(for: item.speciesID),
                    count: item.count,
                    weightGrams: item.weightGrams,
                    lengthMillimeters: item.lengthMillimeters,
                    released: item.released
                )
            }

            if !report.media.isEmpty {
                ReportPhotoStrip(media: report.media, urls: photoURLs)
            }

            ReactionButton(key: ReactionKey(.checkin, report.id), isOwn: report.isOwn)
        }
        .cardContentPadding()
        .cardStyle()
    }

    private var author: String {
        if report.isOwn { return String(localized: "report.you") }
        if let username = report.authorUsername { return "@" + username }
        return report.authorDisplayName ?? String(localized: "profile.noName")
    }

    private var conditionsText: String? {
        ConditionsText.make(report.conditions)
    }
}
