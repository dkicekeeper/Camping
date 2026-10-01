import Backend
import DaladaCore
import DaladaUI
import DesignComponents
import DesignTokens
import MapEngine
import Persistence
import SwiftUI

// MARK: - Вкладка «Места»

/// Вкладка «Места»: поиск и фильтр по типам, подборки (рядом, популярные, где были друзья,
/// подборки редакции, свежие отчёты, новые), «Мои места» и «Сохранённые».
struct PlacesHomeView: View {
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @Environment(PlacesStore.self) private var store
    @State private var query = PlaceQuery()
    @State private var selected: PlaceSelection?

    private var viewerID: UUID? { session.profile?.id }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.xl) {
                    PlaceTypeChips(selection: $query.types)
                    if query.isActive {
                        PlaceResultsList(
                            query: query,
                            location: store.location,
                            environment: environment,
                            onSelect: { selected = PlaceSelection(id: $0) }
                        )
                    } else {
                        discoverContent
                    }
                }
                .padding(.vertical, AppSpacing.md)
            }
            .navigationTitle("tab.places")
            .searchable(text: $query.text, prompt: Text("places.search.prompt"))
            .navigationDestination(for: PlaceListRoute.self) { route in
                PlaceListScreen(route: route, environment: environment)
            }
            .task(id: viewerID) { await store.load(viewer: viewerID) }
            .refreshable { await store.load(viewer: viewerID) }
            .sheet(item: $selected, onDismiss: { Task { await store.load(viewer: viewerID) } }) { selection in
                PlaceCardView(placeID: selection.id, environment: environment)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private var discoverContent: some View {
        if store.isShowingSavedCopy {
            Label("offline.savedCopy", systemImage: "icloud.slash")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .screenPadding()
        }

        if session.profile != nil {
            VStack(spacing: AppSpacing.sm) {
                NavigationLink(value: PlaceListRoute.mine) {
                    PlaceShortcutRow(titleKey: "places.mine.title", systemImage: "mappin.and.ellipse")
                }
                NavigationLink(value: PlaceListRoute.saved) {
                    PlaceShortcutRow(titleKey: "places.saved.title", systemImage: "bookmark")
                }
            }
            .buttonStyle(.plain)
            .screenPadding()
        }

        if store.canAskForLocation {
            Button {
                Task { await store.locate(viewer: viewerID) }
            } label: {
                Label("places.nearby.locate", systemImage: "location")
                    .frame(maxWidth: .infinity)
            }
            .secondaryButton()
            .screenPadding()
        }

        section(.nearby)
        section(.popular)
        section(.friends)
        ForEach(store.discovery.recommended) { collection in
            PlaceCarousel(
                title: collection.title(language: AppConfig.interfaceLanguage),
                systemImage: "checkmark.seal",
                items: collection.places,
                photoURLs: store.photoURLs,
                seeAll: .collection(id: collection.id, title: collection.title(language: AppConfig.interfaceLanguage)),
                onSelect: { selected = PlaceSelection(id: $0) }
            )
        }
        section(.fresh)
        section(.new)

        if store.hasLoaded && PlacesStore.allItems(store.discovery).isEmpty {
            EmptyStateView(
                icon: store.loadError == nil ? "mappin.and.ellipse" : "wifi.slash",
                title: String(localized: "places.empty.title"),
                description: store.loadError ?? String(localized: "places.discover.empty")
            )
        } else if !store.hasLoaded && store.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, AppSpacing.xl)
        }
    }

    @ViewBuilder
    private func section(_ section: PlaceSection) -> some View {
        let items = store.discovery.items(section)
        if !items.isEmpty {
            PlaceCarousel(
                title: String(localized: String.LocalizationValue(section.titleKey)),
                systemImage: section.systemImage,
                items: items,
                photoURLs: store.photoURLs,
                seeAll: section.fullListSort == nil ? nil : .section(section),
                onSelect: { selected = PlaceSelection(id: $0) }
            )
        }
    }
}

/// Куда ведёт «Все» и строки «Мои места» / «Сохранённые».
enum PlaceListRoute: Hashable {
    case section(PlaceSection)
    case collection(id: UUID, title: String)
    case saved
    case mine
}

/// Строка-переход: «Мои места», «Сохранённые».
private struct PlaceShortcutRow: View {
    let titleKey: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: systemImage)
                .foregroundStyle(AppColors.accent)
                .frame(width: AppIconSize.md)
            Text(titleKey)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(AppSpacing.md)
        .cardStyle()
        .contentShape(Rectangle())
    }
}

// MARK: - Фильтр по типам

/// Чипы типов мест: несколько можно выбрать сразу, «Все» сбрасывает.
struct PlaceTypeChips: View {
    @Binding var selection: Set<PlaceType>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                chip(titleKey: "places.filter.all", systemImage: nil, isOn: selection.isEmpty) {
                    selection = []
                }
                ForEach(PlaceType.allCases) { type in
                    chip(titleKey: LocalizedStringKey(type.titleKey), systemImage: type.systemImage,
                         isOn: selection.contains(type)) {
                        if selection.contains(type) {
                            selection.remove(type)
                        } else {
                            selection.insert(type)
                        }
                    }
                }
            }
            .screenPadding()
        }
    }

    private func chip(
        titleKey: LocalizedStringKey,
        systemImage: String?,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(titleKey)
            }
            .font(AppTypography.bodySmall)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .foregroundStyle(isOn ? AppColors.staticWhite : AppColors.textPrimary)
            .background(isOn ? AppColors.accent : AppColors.bgMuted, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Подборка-карусель

/// Заголовок подборки, «Все» и карточки мест в ряд.
private struct PlaceCarousel: View {
    let title: String
    let systemImage: String
    let items: [PlaceItem]
    let photoURLs: [String: URL]
    let seeAll: PlaceListRoute?
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: AppSpacing.sm)
                if let seeAll {
                    NavigationLink(value: seeAll) {
                        Text("places.section.all")
                            .font(AppTypography.bodySmall)
                    }
                }
            }
            .screenPadding()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: AppSpacing.md) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item.id)
                        } label: {
                            PlaceItemCard(item: item, photoURL: item.photoPath.flatMap { photoURLs[$0] })
                        }
                        .buttonStyle(.plain)
                    }
                }
                .screenPadding()
            }
        }
    }
}

/// Карточка места в карусели: фото или значок типа, название, расстояние, оценка, друзья.
private struct PlaceItemCard: View {
    let item: PlaceItem
    let photoURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ZStack(alignment: .topTrailing) {
                PlaceItemImage(item: item, photoURL: photoURL)
                    .frame(width: 200, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                if item.isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.staticWhite)
                        .padding(AppSpacing.xs)
                        .background(AppColors.accent, in: Circle())
                        .padding(AppSpacing.xs)
                        .accessibilityLabel(Text("place.card.saved"))
                }
            }
            HStack(spacing: AppSpacing.xxs) {
                Text(verbatim: item.name)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                if item.isEditorial {
                    Image(systemName: "checkmark.seal.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.accent)
                        .accessibilityLabel(Text("place.card.editorial"))
                }
            }
            PlaceItemMeta(item: item)
        }
        .frame(width: 200, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Фото места или значок его типа на цветном фоне.
private struct PlaceItemImage: View {
    let item: PlaceItem
    let photoURL: URL?

    var body: some View {
        if let path = item.photoPath {
            RemotePhoto(path: path, url: photoURL)
                .background(AppColors.bgMuted)
        } else {
            ZStack {
                AppColors.accent.opacity(0.12)
                Image(systemName: item.type.systemImage)
                    .font(.system(size: AppIconSize.md * 1.5))
                    .foregroundStyle(AppColors.accent)
            }
        }
    }
}

/// Строка под названием: тип, расстояние, оценка, последний отчёт, друзья.
private struct PlaceItemMeta: View {
    let item: PlaceItem

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(spacing: AppSpacing.xs) {
                Text(LocalizedStringKey(item.type.titleKey))
                if let distance = item.distanceM {
                    Text(verbatim: "·")
                    Text(verbatim: TripFormat.distance(Double(distance)))
                }
                if let rating = item.ratingAvg {
                    Text(verbatim: "·")
                    Label {
                        Text(verbatim: rating.formatted(.number.precision(.fractionLength(1))))
                    } icon: {
                        Image(systemName: "star.fill")
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
            .lineLimit(1)
            if let last = item.lastReportAt {
                Text("places.item.lastReport \(Text(last, format: .relative(presentation: .named)))")
                    .lineLimit(1)
            }
            if !item.friends.isEmpty {
                Text("places.item.friends \(item.friends.map(\.shortName).joined(separator: ", "))")
                    .lineLimit(1)
            }
        }
        .font(AppTypography.caption)
        .foregroundStyle(AppColors.textSecondary)
    }
}

/// Строка места в полном списке.
private struct PlaceItemRow: View {
    let item: PlaceItem
    let photoURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            PlaceItemImage(item: item, photoURL: photoURL)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack(spacing: AppSpacing.xxs) {
                    Text(verbatim: item.name)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)
                    if item.isEditorial {
                        Image(systemName: "checkmark.seal.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.accent)
                            .accessibilityLabel(Text("place.card.editorial"))
                    }
                    if item.isSaved {
                        Image(systemName: "bookmark.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.accent)
                            .accessibilityLabel(Text("place.card.saved"))
                    }
                }
                PlaceItemMeta(item: item)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Результаты поиска и полные списки

/// Результаты поиска на вкладке: сортировка, список (подгружается при прокрутке).
private struct PlaceResultsList: View {
    let query: PlaceQuery
    let location: GeoPoint?
    let environment: AppEnvironment
    let onSelect: (UUID) -> Void

    @State private var sort: PlaceSort?
    @State private var items: [PlaceItem] = []
    @State private var photoURLs: [String: URL] = [:]
    @State private var isLoading = false
    @State private var loadError: String?

    private var effectiveQuery: PlaceQuery {
        var query = query
        query.sort = sort
        return query
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Spacer()
                PlaceSortMenu(
                    sort: $sort,
                    hasQuery: !query.trimmedText.isEmpty,
                    hasLocation: location != nil
                )
            }
            .screenPadding()

            if items.isEmpty {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    EmptyStateView(
                        icon: loadError == nil ? "magnifyingglass" : "wifi.slash",
                        title: String(localized: "places.search.empty.title"),
                        description: loadError ?? String(localized: "places.search.empty.description")
                    )
                }
            } else {
                ForEach(items) { item in
                    Button {
                        onSelect(item.id)
                    } label: {
                        PlaceItemRow(item: item, photoURL: item.photoPath.flatMap { photoURLs[$0] })
                    }
                    .buttonStyle(.plain)
                    .screenPadding()
                }
            }
        }
        // Ждём паузу в наборе, чтобы не искать на каждую букву.
        .task(id: effectiveQuery) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        guard let backend = environment.backend else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let found = try await backend.searchPlaces(effectiveQuery, near: location)
            guard !Task.isCancelled else { return }
            items = found
            loadError = nil
            let paths = found.compactMap(\.photoPath)
            if !paths.isEmpty, let urls = try? await backend.signedMediaURLs(paths: paths) {
                photoURLs.merge(urls) { _, new in new }
            }
        } catch is CancellationError {
            return
        } catch {
            items = []
            loadError = error.localizedDescription
        }
    }
}

/// Меню сортировки: только подходящие варианты (без позиции нет «по расстоянию»).
private struct PlaceSortMenu: View {
    @Binding var sort: PlaceSort?
    let hasQuery: Bool
    let hasLocation: Bool

    private var current: PlaceSort {
        let options = PlaceSort.options(hasQuery: hasQuery, hasLocation: hasLocation)
        if let sort, options.contains(sort) { return sort }
        return PlaceSort.defaultSort(hasQuery: hasQuery, hasLocation: hasLocation)
    }

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { current }, set: { sort = $0 })) {
                ForEach(PlaceSort.options(hasQuery: hasQuery, hasLocation: hasLocation)) { option in
                    Text(LocalizedStringKey(option.titleKey)).tag(option)
                }
            } label: {
                Text("places.sort.title")
            }
        } label: {
            Label(LocalizedStringKey(current.titleKey), systemImage: "arrow.up.arrow.down")
                .font(AppTypography.bodySmall)
        }
    }
}

/// Полный список: подборка («Все»), подборка редакции, сохранённые. Список или карта.
struct PlaceListScreen: View {
    let route: PlaceListRoute
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @Environment(PlacesStore.self) private var store
    @State private var items: [PlaceItem] = []
    @State private var photoURLs: [String: URL] = [:]
    @State private var types: Set<PlaceType> = []
    @State private var sort: PlaceSort?
    @State private var showsMap = false
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isShowingSavedCopy = false
    @State private var selected: PlaceSelection?

    var body: some View {
        Group {
            if case .mine = route {
                MyPlacesList(environment: environment)
            } else if showsMap {
                mapContent
            } else {
                listContent
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if route != .mine {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker(selection: $showsMap) {
                        Label("places.view.list", systemImage: "list.bullet").tag(false)
                        Label("places.view.map", systemImage: "map").tag(true)
                    } label: {
                        Text("places.view.list")
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .task(id: LoadKey(route: route, types: types, sort: sort, viewer: session.profile?.id)) { await load() }
        .sheet(item: $selected, onDismiss: { Task { await load() } }) { selection in
            PlaceCardView(placeID: selection.id, environment: environment)
                .presentationDetents([.medium, .large])
        }
    }

    private struct LoadKey: Hashable {
        let route: PlaceListRoute
        let types: Set<PlaceType>
        let sort: PlaceSort?
        let viewer: UUID?
    }

    private var title: String {
        switch route {
        case .section(let section): String(localized: String.LocalizationValue(section.titleKey))
        case .collection(_, let title): title
        case .saved: String(localized: "places.saved.title")
        case .mine: String(localized: "places.mine.title")
        }
    }

    /// Фильтр по типам на сервере есть только у подборок «Все»; у остальных — фильтр на телефоне.
    private var visibleItems: [PlaceItem] {
        if case .section = route { return items }
        return types.isEmpty ? items : items.filter { types.contains($0.type) }
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.md) {
                PlaceTypeChips(selection: $types)
                if case .section = route {
                    HStack {
                        Spacer()
                        PlaceSortMenu(sort: $sort, hasQuery: false, hasLocation: store.location != nil)
                    }
                    .screenPadding()
                }
                if isShowingSavedCopy {
                    Label("offline.savedCopy", systemImage: "icloud.slash")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .screenPadding()
                }
                if visibleItems.isEmpty {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if route == .saved && types.isEmpty && loadError == nil {
                        EmptyStateView(
                            icon: "bookmark",
                            title: String(localized: "places.saved.empty.title"),
                            description: String(localized: "places.saved.empty.description")
                        )
                    } else {
                        EmptyStateView(
                            icon: loadError == nil ? "magnifyingglass" : "wifi.slash",
                            title: String(localized: "places.search.empty.title"),
                            description: loadError ?? String(localized: "places.search.empty.description")
                        )
                    }
                } else {
                    ForEach(visibleItems) { item in
                        Button {
                            selected = PlaceSelection(id: item.id)
                        } label: {
                            PlaceItemRow(item: item, photoURL: item.photoPath.flatMap { photoURLs[$0] })
                        }
                        .buttonStyle(.plain)
                        .screenPadding()
                    }
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .refreshable { await load() }
    }

    private var mapContent: some View {
        DaladaMapView(
            styleURL: environment.config.mapStyleURL,
            initialCenter: visibleItems.first?.coordinate ?? store.location ?? .almaty,
            initialZoom: 8,
            places: visibleItems.map {
                MapPlace(
                    id: $0.id,
                    coordinate: $0.coordinate,
                    isOwn: $0.isOwn,
                    approximateRadiusM: $0.isApproximate ? $0.radiusM : nil
                )
            },
            onPlaceTap: { selected = PlaceSelection(id: $0) }
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private func load() async {
        guard let backend = environment.backend else { return }
        let location = store.location
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded: [PlaceItem]
            switch route {
            case .section(let section):
                loaded = try await backend.searchPlaces(
                    PlaceQuery(types: types, sort: sort ?? section.fullListSort),
                    near: location,
                    limit: 100
                )
            case .collection(let id, _):
                loaded = try await backend.placeCollection(id: id, near: location)
            case .saved:
                loaded = try await backend.savedPlaces(near: location)
                if let viewer = session.profile?.id {
                    try? await environment.cache.save(loaded, for: .savedPlaces(viewer))
                }
            case .mine:
                return
            }
            items = loaded
            loadError = nil
            isShowingSavedCopy = false
            let paths = loaded.compactMap(\.photoPath)
            if !paths.isEmpty, let urls = try? await backend.signedMediaURLs(paths: paths) {
                photoURLs.merge(urls) { _, new in new }
            }
        } catch is CancellationError {
            return
        } catch {
            if route == .saved, let viewer = session.profile?.id,
               let saved = try? await environment.cache.load([PlaceItem].self, for: .savedPlaces(viewer)) {
                items = saved
                isShowingSavedCopy = true
            } else {
                loadError = error.localizedDescription
            }
        }
    }
}

// MARK: - Мои места

/// «Мои места»: свои места любой видимости, включая места на модерации. Без сети — сохранённый
/// список.
private struct MyPlacesList: View {
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @State private var places: [PlaceSummary] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selected: PlaceSelection?

    var body: some View {
        content
            .task(id: session.profile?.id) { await load() }
            .refreshable { await load() }
            .sheet(item: $selected, onDismiss: { Task { await load() } }) { selection in
                PlaceCardView(placeID: selection.id, environment: environment)
                    .presentationDetents([.medium, .large])
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

// MARK: - Закладка в карточке места

/// «Сохранить» в карточке места: закладка в панели. Состояние — своя строка `saved_places`.
struct SavePlaceButton: View {
    let placeID: UUID
    let environment: AppEnvironment

    /// Есть не везде, где открывается карточка: тогда подборки обновятся при следующей загрузке.
    @Environment(PlacesStore.self) private var store: PlacesStore?
    @State private var isSaved: Bool?
    @State private var isWorking = false
    @State private var failed = false

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            Image(systemName: isSaved == true ? "bookmark.fill" : "bookmark")
        }
        .disabled(isSaved == nil || isWorking)
        .accessibilityLabel(Text(isSaved == true ? "place.card.saved" : "place.card.save"))
        .task(id: placeID) {
            isSaved = try? await environment.backend?.isPlaceSaved(placeID)
        }
        .alert("place.card.save.failed", isPresented: $failed) {
            Button("common.ok", role: .cancel) {}
        }
    }

    private func toggle() async {
        guard let backend = environment.backend, let current = isSaved else { return }
        isWorking = true
        defer { isWorking = false }
        isSaved = !current
        do {
            try await backend.setPlaceSaved(placeID, saved: !current)
            store?.setSaved(!current, placeID: placeID)
        } catch {
            isSaved = current
            failed = true
        }
    }
}
