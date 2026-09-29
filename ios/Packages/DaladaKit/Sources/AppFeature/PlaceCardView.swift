import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

/// Карточка места (RPC `place_card`): тип, название, видимость, описание, автор, маршрут.
struct PlaceCardView: View {
    let placeID: UUID
    let backend: BackendClient?

    @Environment(\.openURL) private var openURL
    @State private var state: LoadState = .loading

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

                if let destination = routeDestination(place) {
                    Button {
                        openURL(Self.appleMapsURL(to: destination))
                    } label: {
                        Label("place.card.route", systemImage: "arrow.triangle.turn.up.right.diamond")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryButton()
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
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
            } else {
                state = .notFound
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
