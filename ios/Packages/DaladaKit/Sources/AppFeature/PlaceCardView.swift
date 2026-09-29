import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

/// Карточка места (RPC `place_card`): тип, название, видимость, описание, автор, маршрут,
/// «Я здесь» и свежие отчёты (RPC `place_reports`).
struct PlaceCardView: View {
    let placeID: UUID
    let backend: BackendClient?

    @Environment(\.openURL) private var openURL
    @Environment(SessionStore.self) private var session
    @Environment(SpeciesStore.self) private var speciesStore
    @State private var state: LoadState = .loading
    @State private var reports: [PlaceReport] = []
    /// Подписанные ссылки на фото отчётов: путь в хранилище → ссылка (действует час).
    @State private var photoURLs: [String: URL] = [:]
    @State private var showsCheckin = false

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
        }
        .task { await load() }
        .task { await speciesStore.loadIfNeeded() }
        .sheet(isPresented: $showsCheckin) {
            if case .loaded(let place) = state {
                CheckinFormView(placeID: place.id, placeName: place.name, backend: backend) {
                    Task { await loadReports() }
                }
                .environment(speciesStore)
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

                if let username = place.ownerUsername, !place.isOwn {
                    Text(verbatim: "@" + username)
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
                        Button {
                            openURL(Self.appleMapsURL(to: destination))
                        } label: {
                            Label("place.card.route", systemImage: "arrow.triangle.turn.up.right.diamond")
                                .frame(maxWidth: .infinity)
                        }
                        .secondaryButton()
                    }
                }

                reportsSection
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
        }
    }

    @ViewBuilder
    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeaderView(String(localized: "place.card.reports"), systemImage: "clock")
            if reports.isEmpty {
                Text("place.card.reports.empty")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                ForEach(reports) { report in
                    ReportRow(report: report, photoURLs: photoURLs)
                }
            }
        }
    }

    /// Куда строить маршрут: точка подъезда, иначе само место. Для огрублённого места без точки
    /// подъезда маршрут не строим — иначе раскрыли бы примерную точку как точную.
    private func routeDestination(_ place: PlaceDetails) -> GeoPoint? {
        if let access = place.accessPoint { return access }
        return place.isApproximate ? nil : place.coordinate
    }

    private static func appleMapsURL(to point: GeoPoint) -> URL {
        URL(string: "https://maps.apple.com/?daddr=\(point.latitude),\(point.longitude)")!
    }

    private func load() async {
        guard let backend else {
            state = .failed(String(localized: "backend.status.notConfigured"))
            return
        }
        state = .loading
        do {
            if let place = try await backend.placeDetails(id: placeID) {
                state = .loaded(place)
                await loadReports()
            } else {
                state = .notFound
            }
        } catch {
            state = .failed(error.localizedDescription)
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
    }
}

/// Отчёт в карточке места: автор, время, подтверждение, условия, заметка, уловы, фото.
struct ReportRow: View {
    let report: PlaceReport
    let photoURLs: [String: URL]

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
        }
        .cardContentPadding()
        .cardStyle()
    }

    private var author: String {
        if report.isOwn { return String(localized: "report.you") }
        if let username = report.authorUsername { return "@" + username }
        return report.authorDisplayName ?? String(localized: "profile.noName")
    }

    /// «Клёв: хороший · Людей: немного · Вода: мутная».
    private var conditionsText: String? {
        let conditions = report.conditions
        let pairs: [(String, String?)] = [
            ("conditions.bite", conditions.bite?.titleKey),
            ("conditions.crowd", conditions.crowd?.titleKey),
            ("conditions.water", conditions.water?.titleKey),
            ("conditions.road", conditions.road?.titleKey),
        ]
        let parts = pairs.compactMap { pair -> String? in
            let (category, value) = pair
            guard let value else { return nil }
            let categoryTitle = String(localized: String.LocalizationValue(category))
            let valueTitle = String(localized: String.LocalizationValue(value)).lowercased()
            return categoryTitle + ": " + valueTitle
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
