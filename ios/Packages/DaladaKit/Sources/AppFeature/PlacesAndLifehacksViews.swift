import Backend
import DaladaCore
import DaladaUI
import DesignTokens
import Persistence
import SwiftUI

/// Вкладка «Места». Пока — «Мои места»; подборки (популярные, где были друзья) — в M4.
/// Без сети — сохранённый список.
struct PlacesHomeView: View {
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @State private var places: [PlaceSummary] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selected: PlaceSelection?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("tab.places")
                .task(id: session.profile?.id) { await load() }
                .refreshable { await load() }
                .sheet(item: $selected, onDismiss: { Task { await load() } }) { selection in
                    PlaceCardView(placeID: selection.id, environment: environment)
                        .presentationDetents([.medium, .large])
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if session.profile == nil {
            PlaceholderScreen(
                icon: "mappin.and.ellipse",
                title: String(localized: "places.empty.title"),
                description: String(localized: "places.guest.description")
            )
        } else if places.isEmpty {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PlaceholderScreen(
                    icon: "mappin.and.ellipse",
                    title: String(localized: "places.mine.empty.title"),
                    description: loadError ?? String(localized: "places.mine.empty.description")
                )
            }
        } else {
            List {
                Section("places.mine.title") {
                    ForEach(places) { place in
                        Button {
                            selected = PlaceSelection(id: place.id)
                        } label: {
                            PlaceRow(place: place)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func load() async {
        guard let userID = session.profile?.id, let backend = environment.backend else {
            places = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        let key = CacheKey.myPlaces(userID)
        do {
            places = try await backend.myPlaces()
            loadError = nil
            try? await environment.cache.save(places, for: key)
        } catch {
            if let saved = try? await environment.cache.load([PlaceSummary].self, for: key) {
                places = saved
            } else {
                loadError = error.localizedDescription
            }
        }
    }
}

/// Строка места: иконка типа, название, видимость, статус модерации.
struct PlaceRow: View {
    let place: PlaceSummary

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: place.type.systemImage)
                .font(.system(size: AppIconSize.md))
                .foregroundStyle(AppColors.accent)
                .frame(width: AppIconSize.avatar, height: AppIconSize.avatar)
                .background(AppColors.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: place.name)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                HStack(spacing: AppSpacing.sm) {
                    Label(LocalizedStringKey(place.visibility.titleKey), systemImage: place.visibility.systemImage)
                    if place.status == .pending {
                        Label("place.status.pending", systemImage: "hourglass")
                            .foregroundStyle(AppColors.warning)
                    }
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Вкладка «Лайфхаки» — заглушка до этапа M5.
struct LifehacksHomeView: View {
    var body: some View {
        NavigationStack {
            PlaceholderScreen(
                icon: "checklist",
                title: String(localized: "lifehacks.empty.title"),
                description: String(localized: "lifehacks.empty.description")
            )
            .navigationTitle("tab.lifehacks")
        }
    }
}

#Preview("Лайфхаки") { LifehacksHomeView() }
