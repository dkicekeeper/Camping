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

/// Вкладка «Лайфхаки»: правила и запреты, справочник рыб. Чеклисты, экипировка и статьи —
/// в следующих частях M5.
struct LifehacksHomeView: View {
    let environment: AppEnvironment

    @Environment(RulesStore.self) private var rules

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        RulesListView(environment: environment)
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Label("rules.title", systemImage: "exclamationmark.shield")
                                .font(AppTypography.bodyEmphasis)
                            if let summary = rulesSummary {
                                Text(verbatim: summary)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                    NavigationLink {
                        FishGuideView()
                    } label: {
                        Label("fish.guide.title", systemImage: "fish")
                            .font(AppTypography.bodyEmphasis)
                    }
                } header: {
                    Text("lifehacks.section.knowledge")
                }

                Section {
                    Text("lifehacks.soon")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                } header: {
                    Text("lifehacks.section.soon")
                }
            }
            .navigationTitle("tab.lifehacks")
            .task { await rules.loadIfNeeded() }
        }
    }

    /// «Сейчас действуют запреты: 2» или ближайший: «Капшагайское водохранилище — с 5 апреля».
    private var rulesSummary: String? {
        guard let pack = rules.pack else { return nil }
        let today = RulesStore.today
        let active = pack.zones.filter { pack.banState(ofZone: $0.id, on: today) == .active }
        if !active.isEmpty {
            return String(localized: "rules.summary.active \(active.count)")
        }
        let upcoming = pack.regulations
            .filter { $0.kind == .fishingBan }
            .compactMap { regulation -> (Regulation, CalendarDay)? in
                switch pack.status(of: regulation, on: today) {
                case .soon(let start, _, _), .later(let start, _): (regulation, start)
                case .active, .yearRound: nil
                }
            }
            .min { $0.1 < $1.1 }
        guard let next = upcoming,
              let zoneID = next.0.zoneIDs.first,
              let zone = pack.zone(zoneID)
        else { return nil }
        return String(localized: "rules.summary.next \(zone.name.text(for: RulesStore.language)) \(RuleFormat.day(next.1))")
    }
}
