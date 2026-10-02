import Backend
import DaladaCore
import DaladaUI
import DesignComponents
import DesignTokens
import MapEngine
import Persistence
import SwiftUI

// MARK: - Профиль другого человека: поездки, места, итоги

/// Поездки, места и итоги человека — то, что я вижу по их видимости.
struct UserContentSections: View {
    let userID: UUID
    let isFriend: Bool
    let environment: AppEnvironment

    @State private var stats: UserPublicStats?
    @State private var trips: [TripSummary] = []
    @State private var places: [PlaceSummary] = []
    @State private var isLoaded = false
    @State private var selectedPlace: PlaceSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            if let stats {
                UserStatsCard(stats: stats)
            }

            if !trips.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack {
                        SectionHeaderView(String(localized: "person.trips"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        Spacer(minLength: 0)
                        NavigationLink {
                            UserTripsListView(userID: userID, environment: environment)
                        } label: {
                            Text("trips.all")
                                .font(AppTypography.bodySmall)
                        }
                    }
                    VStack(spacing: AppSpacing.md) {
                        ForEach(trips.prefix(3)) { trip in
                            NavigationLink {
                                TripDetailView(tripID: trip.id, environment: environment)
                            } label: {
                                TripRow(trip: trip)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .cardContentPadding()
                    .cardStyle()
                }
            }

            if !places.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack {
                        SectionHeaderView(String(localized: "person.places"), systemImage: "mappin.and.ellipse")
                        Spacer(minLength: 0)
                        if places.count > 5 {
                            NavigationLink {
                                UserPlacesListView(places: places, environment: environment)
                            } label: {
                                Text("trips.all")
                                    .font(AppTypography.bodySmall)
                            }
                        }
                    }
                    VStack(spacing: AppSpacing.md) {
                        ForEach(places.prefix(5)) { place in
                            Button {
                                selectedPlace = PlaceSelection(id: place.id)
                            } label: {
                                PlaceRow(place: place)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .cardContentPadding()
                    .cardStyle()
                }
            }

            if isLoaded && trips.isEmpty && places.isEmpty {
                Text(LocalizedStringKey(isFriend ? "person.nothingShared" : "person.friendsOnlyHint"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .task(id: "\(userID)-\(isFriend)") { await load() }
        .sheet(item: $selectedPlace) { selection in
            PlaceCardView(placeID: selection.id, environment: environment)
                .presentationDetents([.medium, .large])
        }
    }

    private func load() async {
        defer { isLoaded = true }
        guard let backend = environment.backend else { return }
        async let loadedStats = backend.userStats(userID)
        async let loadedTrips = backend.userTrips(userID, limit: 3)
        async let loadedPlaces = backend.userPlaces(userID)
        stats = try? await loadedStats
        trips = (try? await loadedTrips) ?? []
        places = (try? await loadedPlaces) ?? []
    }
}

/// Итоги человека: поездки, километры, места, уловы.
struct UserStatsCard: View {
    let stats: UserPublicStats

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            StatTile(title: String(localized: "person.stats.trips"), value: "\(stats.tripsCount)")
            StatTile(title: String(localized: "person.stats.distance"), value: TripFormat.distance(Double(stats.distanceM)))
            StatTile(title: String(localized: "person.stats.places"), value: "\(stats.placesCount)")
            StatTile(title: String(localized: "person.stats.catches"), value: "\(stats.catchesCount)")
        }
        .cardContentPadding()
        .cardStyle()
    }
}

/// Все поездки человека, которые я вижу; следующая страница — при прокрутке до конца.
struct UserTripsListView: View {
    let userID: UUID
    let environment: AppEnvironment

    private static let pageSize = 30

    @State private var trips: [TripSummary] = []
    @State private var hasMore = true
    @State private var isLoaded = false

    var body: some View {
        Group {
            if trips.isEmpty && isLoaded {
                PlaceholderScreen(
                    icon: "figure.hiking",
                    title: String(localized: "person.trips.empty"),
                    description: String(localized: "person.friendsOnlyHint")
                )
            } else {
                List {
                    ForEach(trips) { trip in
                        NavigationLink {
                            TripDetailView(tripID: trip.id, environment: environment)
                        } label: {
                            TripRow(trip: trip)
                        }
                        .onAppear {
                            if trip.id == trips.last?.id { Task { await loadMore() } }
                        }
                    }
                }
            }
        }
        .navigationTitle("person.trips")
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        defer { isLoaded = true }
        guard let backend = environment.backend,
              let page = try? await backend.userTrips(userID, limit: Self.pageSize)
        else { return }
        trips = page
        hasMore = page.count >= Self.pageSize
    }

    private func loadMore() async {
        guard hasMore, let backend = environment.backend, let last = trips.last,
              let page = try? await backend.userTrips(userID, limit: Self.pageSize, before: last.startedAt)
        else { return }
        let known = Set(trips.map(\.id))
        trips += page.filter { !known.contains($0.id) }
        hasMore = page.count >= Self.pageSize
    }
}

/// Все места человека, которые я вижу.
struct UserPlacesListView: View {
    let places: [PlaceSummary]
    let environment: AppEnvironment

    @State private var selectedPlace: PlaceSelection?

    var body: some View {
        List(places) { place in
            Button {
                selectedPlace = PlaceSelection(id: place.id)
            } label: {
                PlaceRow(place: place)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("person.places")
        .sheet(item: $selectedPlace) { selection in
            PlaceCardView(placeID: selection.id, environment: environment)
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Зоны приватности

/// Зоны приватности: другие не видят участки ваших треков рядом с домом, дачей.
struct PrivacyZonesView: View {
    let environment: AppEnvironment

    @State private var zones: [PrivacyZone] = []
    @State private var isLoaded = false
    @State private var loadError: String?
    @State private var editing: EditorRequest?

    /// Открытый редактор: новая зона (`zone == nil`) или изменение.
    struct EditorRequest: Identifiable {
        let id = UUID()
        let zone: PrivacyZone?
    }

    var body: some View {
        List {
            Section {
                Text("privacyZones.explanation")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Section {
                ForEach(zones) { zone in
                    Button {
                        editing = EditorRequest(zone: zone)
                    } label: {
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: "house.circle.fill")
                                .font(.system(size: AppIconSize.md))
                                .foregroundStyle(AppColors.accent)
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text(verbatim: zone.name)
                                    .font(AppTypography.bodyEmphasis)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text("privacyZones.radius \(TripFormat.distance(Double(zone.radiusM)))")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    let removed = offsets.map { zones[$0] }
                    Task { await delete(removed) }
                }

                if isLoaded && loadError == nil && zones.count < PrivacyZone.limit {
                    Button {
                        editing = EditorRequest(zone: nil)
                    } label: {
                        Label("privacyZones.add", systemImage: "plus.circle")
                    }
                }
            } footer: {
                if let loadError {
                    Text(verbatim: loadError)
                        .foregroundStyle(AppColors.destructive)
                } else if zones.count >= PrivacyZone.limit {
                    Text("privacyZones.limit")
                }
            }
        }
        .navigationTitle("privacyZones.title")
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { request in
            PrivacyZoneEditorView(zone: request.zone, environment: environment)
        }
    }

    private func load() async {
        defer { isLoaded = true }
        guard let backend = environment.backend else {
            loadError = String(localized: "backend.status.notConfigured")
            return
        }
        do {
            zones = try await backend.privacyZones()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func delete(_ removed: [PrivacyZone]) async {
        guard let backend = environment.backend else { return }
        for zone in removed {
            try? await backend.deletePrivacyZone(zone.id)
        }
        await load()
    }
}

/// Новая или изменённая зона: центр — перекрестье карты, радиус 200–1000 м, название.
struct PrivacyZoneEditorView: View {
    let zone: PrivacyZone?
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PrivacyZoneDraft?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var confirmsDelete = false

    private static let suggestions = ["privacyZones.suggestion.home", "privacyZones.suggestion.dacha", "privacyZones.suggestion.work"]

    var body: some View {
        NavigationStack {
            Group {
                if let binding = Binding($draft) {
                    editor(binding)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(LocalizedStringKey(zone == nil ? "privacyZones.new" : "privacyZones.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("common.save") {
                            Task { await save() }
                        }
                        .disabled(!(draft?.isValid ?? false))
                    }
                }
            }
            .confirmationDialog("privacyZones.deleteConfirm", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("privacyZones.delete", role: .destructive) {
                    Task { await delete() }
                }
            }
        }
        .task {
            guard draft == nil else { return }
            if let zone {
                draft = PrivacyZoneDraft(editing: zone)
            } else {
                draft = PrivacyZoneDraft(center: await DeviceLocation.current(timeout: .seconds(5)) ?? .almaty)
            }
        }
    }

    private func editor(_ draft: Binding<PrivacyZoneDraft>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                ZStack {
                    DaladaMapView(
                        styleURL: environment.config.mapStyleURL,
                        initialCenter: draft.wrappedValue.center,
                        initialZoom: 14,
                        places: [
                            MapPlace(
                                id: draft.wrappedValue.id,
                                coordinate: draft.wrappedValue.center,
                                isOwn: true,
                                approximateRadiusM: draft.wrappedValue.radiusM
                            ),
                        ],
                        onRegionChange: { box in draft.wrappedValue.center = box.center }
                    )
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(AppColors.textPrimary)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl))

                Text("privacyZones.editor.hint")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    TextField("privacyZones.name", text: draft.name)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(Self.suggestions, id: \.self) { key in
                            Button(LocalizedStringKey(key)) {
                                draft.wrappedValue.name = String(localized: String.LocalizationValue(key))
                            }
                            .buttonStyle(.bordered)
                            .font(AppTypography.bodySmall)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        Text("privacyZones.radiusTitle")
                            .font(AppTypography.bodyEmphasis)
                        Spacer(minLength: 0)
                        Text(verbatim: TripFormat.distance(Double(draft.wrappedValue.radiusM)))
                            .font(AppTypography.body)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(draft.wrappedValue.radiusM) },
                            set: { draft.wrappedValue.radiusM = Int($0.rounded()) }
                        ),
                        in: Double(PrivacyZone.radiusRange.lowerBound)...Double(PrivacyZone.radiusRange.upperBound),
                        step: Double(PrivacyZone.radiusStep)
                    )
                    Text("privacyZones.radiusHint")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                if let saveError {
                    Text(verbatim: saveError)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.destructive)
                }

                if zone != nil {
                    Button("privacyZones.delete", role: .destructive) {
                        confirmsDelete = true
                    }
                    .secondaryButton()
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
        }
    }

    private func save() async {
        guard let draft, draft.isValid, let backend = environment.backend else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await backend.savePrivacyZone(draft)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func delete() async {
        guard let zone, let backend = environment.backend else { return }
        do {
            try await backend.deletePrivacyZone(zone.id)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
