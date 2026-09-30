import Backend
import DaladaCore
import DaladaUI
import DesignComponents
import DesignTokens
import MapEngine
import Persistence
import SwiftUI
import Sync

// MARK: - Форматы

/// Числа поездки на языке интерфейса: «12,4 км», «1:23:45», «5 ч 12 мин», «4,2 км/ч», «+85 м».
enum TripFormat {
    static func distance(_ meters: Double) -> String {
        if meters < 1000 {
            return Measurement(value: meters.rounded(), unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        }
        return Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    /// Часы: «1:23:45».
    static func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(max(seconds, 0))).formatted(.time(pattern: .hourMinuteSecond))
    }

    /// Кратко: «5 ч 12 мин».
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(max(seconds, 0))).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func speed(_ metersPerSecond: Double?) -> String {
        guard let metersPerSecond else { return "—" }
        return Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond)
            .converted(to: .kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    static func elevation(_ meters: Double) -> String {
        "+" + Measurement(value: meters.rounded(), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// Название по умолчанию: «Рыбалка · 29 сентября».
    static func defaultTitle(activity: TripActivity, date: Date) -> String {
        String(localized: String.LocalizationValue(activity.titleKey)) + " · " + date.formatted(.dateTime.day().month(.wide))
    }
}

/// Показатель: подпись и крупное число.
struct TripStat: View {
    let titleKey: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(titleKey)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            Text(verbatim: value)
                .font(AppTypography.h4)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Старт

/// Выбор вида поездки и «Старт» (открывается из «+»).
struct StartTripView: View {
    let onStart: @MainActor (TripActivity) -> Void

    @State private var activity: TripActivity = .fishing

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.md) {
                    ForEach(TripActivity.allCases) { item in
                        Button {
                            activity = item
                        } label: {
                            VStack(spacing: AppSpacing.sm) {
                                Image(systemName: item.systemImage)
                                    .font(.system(size: 28))
                                Text(LocalizedStringKey(item.titleKey))
                                    .font(AppTypography.bodyEmphasis)
                            }
                            .foregroundStyle(activity == item ? AppColors.accent : AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.lg)
                            .background(
                                activity == item ? AppColors.accent.opacity(0.15) : AppColors.bgCard,
                                in: RoundedRectangle(cornerRadius: AppRadius.lg)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: AppRadius.lg)
                                    .stroke(activity == item ? AppColors.accent : Color.clear, lineWidth: 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(activity == item ? .isSelected : [])
                    }
                }

                Text("trip.start.hint")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)

                Button {
                    onStart(activity)
                } label: {
                    Label("trip.start.button", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .primaryButton()
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
        }
        .navigationTitle("trip.start.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Запись

/// Экран записи: карта следует за вами, время, дистанция, скорость, набор высоты; пауза и финиш.
/// «Свернуть» оставляет запись идти — вернуться можно из мини-плеера над вкладками.
struct TripRecordingView: View {
    let environment: AppEnvironment

    @Environment(TripRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @State private var finishing: FinishRequest?

    /// Открытый экран финиша: когда нажали «Финиш».
    struct FinishRequest: Identifiable {
        let id = UUID()
        let endedAt: Date
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DaladaMapView(
                styleURL: environment.config.mapStyleURL,
                initialCenter: recorder.track.last ?? .almaty,
                initialZoom: 14,
                trackSegments: [recorder.track],
                cameraMode: .followUser
            )
            .ignoresSafeArea()

            panel
                .padding(AppSpacing.lg)
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(AppTypography.bodyEmphasis)
                    .padding(AppSpacing.md)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel(Text("trip.minimize"))
            .padding(AppSpacing.lg)
        }
        .sheet(item: $finishing) { request in
            TripFinishView(endedAt: request.endedAt) { didClose in
                if didClose { dismiss() }
            }
            .interactiveDismissDisabled()
        }
        .onChange(of: recorder.isActive) { _, isActive in
            if !isActive, finishing == nil { dismiss() }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if recorder.isLocationDenied {
                RecommendationBox(
                    text: String(localized: "trip.location.denied"),
                    color: AppColors.warning,
                    icon: "location.slash"
                )
            }
            HStack {
                Label(LocalizedStringKey(recorder.activity.titleKey), systemImage: recorder.activity.systemImage)
                    .font(AppTypography.bodyEmphasis)
                Spacer(minLength: 0)
                if recorder.phase == .paused {
                    Label("trip.paused", systemImage: "pause.circle.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.warning)
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                TripStat(
                    titleKey: "trip.stat.time",
                    value: TripFormat.clock(context.date.timeIntervalSince(recorder.startedAt ?? context.date))
                )
            }
            HStack(spacing: AppSpacing.md) {
                TripStat(titleKey: "trip.stat.distance", value: TripFormat.distance(recorder.stats.distanceM))
                TripStat(titleKey: "trip.stat.speed", value: TripFormat.speed(recorder.phase == .recording ? recorder.currentSpeed : nil))
                TripStat(titleKey: "trip.stat.elevation", value: TripFormat.elevation(recorder.stats.elevationGainM))
            }
            HStack(spacing: AppSpacing.md) {
                if recorder.phase == .recording {
                    Button {
                        Task { await recorder.pause() }
                    } label: {
                        Label("trip.pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .secondaryButton()
                } else {
                    Button {
                        Task { await recorder.resume() }
                    } label: {
                        Label("trip.resume", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryButton()
                }
                Button {
                    Task {
                        await recorder.pause()
                        finishing = FinishRequest(endedAt: Date())
                    }
                } label: {
                    Label("trip.finish", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .secondaryButton()
            }
        }
        .cardContentPadding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.xl))
    }
}

// MARK: - Финиш

/// Итоги и сохранение: название, вид, заметка, видимость. Или «Удалить поездку».
struct TripFinishView: View {
    let endedAt: Date
    /// `true` — поездка сохранена или удалена, экран записи тоже закрывается.
    let onClose: @MainActor (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(TripRecorder.self) private var recorder
    @Environment(SessionStore.self) private var session
    @Environment(SyncEngine.self) private var sync
    @State private var title = ""
    @State private var note = ""
    @State private var activity: TripActivity = .fishing
    @State private var visibility: DaladaCore.Visibility = .friends
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var confirmsDiscard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: AppSpacing.md) {
                        TripStat(titleKey: "trip.stat.distance", value: TripFormat.distance(recorder.stats.distanceM))
                        TripStat(titleKey: "trip.stat.moving", value: TripFormat.duration(recorder.stats.movingSeconds))
                    }
                    HStack(spacing: AppSpacing.md) {
                        TripStat(
                            titleKey: "trip.stat.duration",
                            value: TripFormat.duration(endedAt.timeIntervalSince(recorder.startedAt ?? endedAt))
                        )
                        TripStat(titleKey: "trip.stat.elevation", value: TripFormat.elevation(recorder.stats.elevationGainM))
                    }
                }

                Section("trip.finish.name") {
                    TextField("trip.finish.name", text: $title)
                    Picker("trip.finish.activity", selection: $activity) {
                        ForEach(TripActivity.allCases) { item in
                            Label(LocalizedStringKey(item.titleKey), systemImage: item.systemImage).tag(item)
                        }
                    }
                }

                Section("checkin.form.note") {
                    TextField("trip.finish.notePlaceholder", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    Picker("place.form.visibility", selection: $visibility) {
                        ForEach(DaladaCore.Visibility.allCases) { item in
                            Text(LocalizedStringKey(item.titleKey)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("place.form.visibility")
                } footer: {
                    Text("trip.finish.visibilityFooter")
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(AppColors.destructive)
                    }
                }

                Section {
                    Button("trip.finish.discard", role: .destructive) {
                        confirmsDiscard = true
                    }
                }
            }
            .navigationTitle("trip.finish.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("trip.finish.back") {
                        onClose(false)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("trip.finish.save") {
                            Task { await save() }
                        }
                        .disabled(!isValid)
                    }
                }
            }
            .confirmationDialog("trip.finish.discardConfirm", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("trip.finish.discard", role: .destructive) {
                    Task {
                        await recorder.discard()
                        onClose(true)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard title.isEmpty else { return }
                activity = recorder.activity
                title = TripFormat.defaultTitle(activity: recorder.activity, date: recorder.startedAt ?? endedAt)
            }
        }
    }

    private var isValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...TripDraft.titleLimit).contains(trimmed.count) && note.count <= TripDraft.noteLimit
    }

    private func save() async {
        guard let owner = session.profile?.id else {
            saveError = String(localized: "trip.signInRequired")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await recorder.finish(
                owner: owner,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                visibility: visibility,
                activity: activity,
                endedAt: endedAt
            )
            await sync.enqueued()
            onClose(true)
            dismiss()
        } catch {
            saveError = String(localized: "trip.finish.failed")
        }
    }
}

// MARK: - Мини-плеер

/// Идущая запись над вкладками: время и дистанция; тап — экран записи.
struct TripMiniPlayer: View {
    let onOpen: @MainActor () -> Void

    @Environment(TripRecorder.self) private var recorder

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: recorder.phase == .paused ? "pause.circle.fill" : "record.circle")
                    .foregroundStyle(recorder.phase == .paused ? AppColors.warning : AppColors.destructive)
                    .symbolEffect(.pulse, isActive: recorder.phase == .recording)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(verbatim: TripFormat.clock(context.date.timeIntervalSince(recorder.startedAt ?? context.date)))
                        .monospacedDigit()
                }
                Text(verbatim: TripFormat.distance(recorder.stats.distanceM))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .foregroundStyle(AppColors.textTertiary)
            }
            .font(AppTypography.bodyEmphasis)
            .padding(.horizontal, AppSpacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("trip.miniPlayer"))
    }
}

/// Мини-плеер в `tabViewBottomAccessory`, пока идёт запись (iOS 26.1+). На iOS 26.0 к записи
/// возвращаются через «+».
struct TripAccessoryModifier: ViewModifier {
    let isEnabled: Bool
    let onOpen: @MainActor () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled) {
                TripMiniPlayer(onOpen: onOpen)
            }
        } else {
            content
        }
    }
}

// MARK: - Мои поездки

/// Строка поездки: вид, название, дата, дистанция и время в движении.
struct TripRow: View {
    let trip: TripSummary

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: trip.activity.systemImage)
                .font(.system(size: AppIconSize.md))
                .foregroundStyle(AppColors.accent)
                .frame(width: AppIconSize.avatar, height: AppIconSize.avatar)
                .background(AppColors.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: trip.title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(verbatim: [
                    trip.startedAt.formatted(.dateTime.day().month().year()),
                    TripFormat.distance(Double(trip.distanceM)),
                    TripFormat.duration(Double(trip.movingSeconds)),
                ].joined(separator: " · "))
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

/// «Мои поездки» в профиле: последние три и «Все поездки». Без сети — сохранённый список.
struct MyTripsSection: View {
    let environment: AppEnvironment
    let userID: UUID

    @Environment(SyncEngine.self) private var sync
    @State private var trips: [TripSummary] = []

    var body: some View {
        Group {
            if !trips.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack {
                        SectionHeaderView(String(localized: "trips.title"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        Spacer(minLength: 0)
                        NavigationLink {
                            TripsListView(environment: environment, userID: userID)
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
        }
        .task(id: userID) { await load() }
        .onChange(of: sync.sentCount) { _, _ in
            Task { await load() }
        }
    }

    private func load() async {
        trips = await TripsLoader(environment: environment, userID: userID).load(limit: 50)
    }
}

/// Все свои поездки.
struct TripsListView: View {
    let environment: AppEnvironment
    let userID: UUID

    @State private var trips: [TripSummary] = []
    @State private var isLoaded = false

    var body: some View {
        Group {
            if trips.isEmpty && isLoaded {
                PlaceholderScreen(
                    icon: "figure.hiking",
                    title: String(localized: "trips.empty.title"),
                    description: String(localized: "trips.empty.description")
                )
            } else {
                List(trips) { trip in
                    NavigationLink {
                        TripDetailView(tripID: trip.id, environment: environment)
                    } label: {
                        TripRow(trip: trip)
                    }
                }
            }
        }
        .navigationTitle("trips.title")
        .task {
            trips = await TripsLoader(environment: environment, userID: userID).load(limit: 200)
            isLoaded = true
        }
        .refreshable {
            trips = await TripsLoader(environment: environment, userID: userID).load(limit: 200)
        }
    }
}

/// Список поездок: сеть, при ошибке — кэш.
struct TripsLoader {
    let environment: AppEnvironment
    let userID: UUID

    func load(limit: Int) async -> [TripSummary] {
        let key = CacheKey.myTrips(userID)
        if let backend = environment.backend, let trips = try? await backend.myTrips(limit: limit) {
            try? await environment.cache.save(trips, for: key)
            return trips
        }
        return (try? await environment.cache.load([TripSummary].self, for: key)) ?? []
    }
}

// MARK: - Страница поездки

/// Поездка: трек на карте, итоги, заметка, чекины за время поездки. Своя — с выбором «Кто видит»;
/// чужая — с автором, трек без начала, конца и скрытых участков.
struct TripDetailView: View {
    let tripID: UUID
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @Environment(SpeciesStore.self) private var speciesStore
    @Environment(ReactionStore.self) private var reactions
    @State private var trip: TripDetails?
    @State private var checkins: [TripCheckin] = []
    @State private var photoURLs: [String: URL] = [:]
    @State private var loadError: String?
    @State private var visibilityError: String?
    @State private var showsVisibilityError = false
    @State private var selectedPlace: PlaceSelection?
    @State private var followed: FollowedRoute?

    var body: some View {
        Group {
            if let trip {
                content(trip)
            } else if let loadError {
                EmptyStateView(
                    icon: "wifi.slash",
                    title: String(localized: "trip.detail.failed"),
                    description: loadError,
                    actionTitle: String(localized: "common.retry"),
                    action: { Task { await load() } },
                    style: .error
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(Text(verbatim: trip?.summary.title ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let trip, trip.isOwn {
                ToolbarItem(placement: .topBarTrailing) {
                    visibilityMenu(trip)
                }
            } else if let trip {
                ToolbarItem(placement: .topBarTrailing) {
                    ModerationMenu(
                        target: .trip,
                        targetID: trip.summary.id,
                        author: trip.owner.map { FeedAuthor(id: $0.id, username: $0.username, displayName: $0.displayName) },
                        isToolbar: true
                    ) {
                        Task { await load() }
                    }
                }
            }
        }
        .alert("trip.visibility.failed", isPresented: $showsVisibilityError) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: visibilityError ?? "")
        }
        .sheet(item: $selectedPlace) { selection in
            PlaceCardView(placeID: selection.id, environment: environment)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $followed) { route in
            FollowRouteView(route: route, environment: environment)
        }
        .task { await load() }
        .task { await speciesStore.loadIfNeeded() }
    }

    private func content(_ trip: TripDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if !trip.isOwn, let owner = trip.owner {
                    TripOwnerRow(owner: owner, environment: environment)
                }

                if let start = trip.track.first {
                    DaladaMapView(
                        styleURL: environment.config.mapStyleURL,
                        initialCenter: start,
                        initialZoom: 12,
                        showsUserLocation: false,
                        trackSegments: trip.segments,
                        cameraMode: .fitTrack
                    )
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl))
                }
                // Пройти по треку: линия маршрута, сколько осталось, предупреждение при сходе.
                if let route = FollowedRoute(trip: trip) {
                    Button {
                        followed = route
                    } label: {
                        Label("route.follow", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .frame(maxWidth: .infinity)
                    }
                    .secondaryButton()
                }
                if !trip.isOwn {
                    Label(
                        LocalizedStringKey(trip.segments.isEmpty ? "trip.detail.trackHiddenAll" : "trip.detail.trackHidden"),
                        systemImage: "eye.slash"
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Label(LocalizedStringKey(trip.summary.activity.titleKey), systemImage: trip.summary.activity.systemImage)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                    Text(verbatim: trip.summary.startedAt.formatted(.dateTime.day().month(.wide).year().hour().minute()))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    if trip.isOwn {
                        Label(LocalizedStringKey(trip.summary.visibility.titleKey), systemImage: trip.summary.visibility.systemImage)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    ReactionButton(key: ReactionKey(.trip, trip.summary.id), isOwn: trip.isOwn)
                }

                VStack(spacing: AppSpacing.md) {
                    HStack(spacing: AppSpacing.md) {
                        TripStat(titleKey: "trip.stat.distance", value: TripFormat.distance(Double(trip.summary.distanceM)))
                        TripStat(titleKey: "trip.stat.moving", value: TripFormat.duration(Double(trip.summary.movingSeconds)))
                    }
                    HStack(spacing: AppSpacing.md) {
                        TripStat(titleKey: "trip.stat.duration", value: TripFormat.duration(trip.summary.duration))
                        TripStat(titleKey: "trip.stat.elevation", value: TripFormat.elevation(Double(trip.summary.elevationGainM)))
                    }
                    HStack(spacing: AppSpacing.md) {
                        TripStat(titleKey: "trip.stat.maxSpeed", value: TripFormat.speed(trip.summary.maxSpeedMps))
                        Spacer(minLength: 0)
                            .frame(maxWidth: .infinity)
                    }
                }
                .cardContentPadding()
                .cardStyle()

                if let note = trip.summary.note, !note.isEmpty {
                    Text(verbatim: note)
                        .font(AppTypography.body)
                }

                if !checkins.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        SectionHeaderView(String(localized: "trip.detail.checkins"), systemImage: "mappin.circle")
                        ForEach(checkins) { checkin in
                            TripCheckinRow(checkin: checkin, photoURLs: photoURLs) {
                                if let placeID = checkin.placeID {
                                    selectedPlace = PlaceSelection(id: placeID)
                                }
                            }
                        }
                    }
                }

                if trip.isOwn && trip.summary.visibility != .private {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("trip.detail.sharedHint")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                        NavigationLink {
                            PrivacyZonesView(environment: environment)
                        } label: {
                            Label("privacyZones.title", systemImage: "house.circle")
                                .font(AppTypography.bodySmall)
                        }
                    }
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
        }
    }

    /// «Кто видит» своей поездки.
    private func visibilityMenu(_ trip: TripDetails) -> some View {
        Menu {
            Section("place.form.visibility") {
                ForEach(DaladaCore.Visibility.allCases) { item in
                    Button {
                        Task { await setVisibility(item) }
                    } label: {
                        Label(
                            LocalizedStringKey(item.titleKey),
                            systemImage: item == trip.summary.visibility ? "checkmark" : item.systemImage
                        )
                    }
                }
            }
        } label: {
            Image(systemName: trip.summary.visibility.systemImage)
                .accessibilityLabel(Text("place.form.visibility"))
        }
    }

    private func setVisibility(_ visibility: DaladaCore.Visibility) async {
        guard let trip, trip.summary.visibility != visibility else { return }
        guard let backend = environment.backend else { return }
        do {
            try await backend.setTripVisibility(trip.summary.id, visibility: visibility)
            let updated = trip.with(visibility: visibility)
            self.trip = updated
            try? await environment.cache.save(updated, for: CacheKey.trip(tripID, viewer: session.profile?.id))
        } catch {
            visibilityError = error.localizedDescription
            showsVisibilityError = true
        }
    }

    private func load() async {
        let key = CacheKey.trip(tripID, viewer: session.profile?.id)
        if let backend = environment.backend {
            do {
                if let loaded = try await backend.tripDetails(id: tripID) {
                    trip = loaded
                    loadError = nil
                    try? await environment.cache.save(loaded, for: key)
                    await reactions.load([ReactionKey(.trip, tripID)])
                    checkins = (try? await backend.tripCheckins(tripID: tripID)) ?? []
                    let paths = checkins.flatMap { checkin in checkin.media.flatMap { [$0.thumbnailPath, $0.path] } }
                    photoURLs = (try? await backend.signedMediaURLs(paths: paths)) ?? [:]
                    return
                }
            } catch {
                loadError = error.localizedDescription
            }
        }
        if let saved = try? await environment.cache.load(TripDetails.self, for: key) {
            trip = saved
            loadError = nil
        } else if loadError == nil {
            loadError = String(localized: "trip.detail.notFound")
        }
    }
}

/// Автор чужой поездки — ссылка на его профиль.
struct TripOwnerRow: View {
    let owner: TripOwner
    let environment: AppEnvironment

    var body: some View {
        if let username = owner.username {
            NavigationLink {
                UserProfileView(username: username, environment: environment)
            } label: {
                PersonRow(displayName: owner.displayName, username: owner.username) {
                    Image(systemName: "chevron.right")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .buttonStyle(.plain)
        } else {
            PersonRow(displayName: owner.displayName, username: nil)
        }
    }
}

/// Чекин поездки: место (тап — карточка места), время, условия, заметка, уловы, фото.
/// Место, которого зритель не видит, — «Секретное место».
struct TripCheckinRow: View {
    let checkin: TripCheckin
    var photoURLs: [String: URL] = [:]
    var onPlaceTap: @MainActor () -> Void = {}

    @Environment(SpeciesStore.self) private var speciesStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                if let placeName = checkin.placeName {
                    Button {
                        onPlaceTap()
                    } label: {
                        Text(verbatim: placeName)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Label("trip.detail.placeHidden", systemImage: "lock")
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColors.textSecondary)
                }
                if checkin.verified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppColors.success)
                        .accessibilityLabel(Text("report.verified"))
                }
                Spacer(minLength: 0)
                Text(verbatim: checkin.at.formatted(.dateTime.hour().minute()))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            if let conditions = ConditionsText.make(checkin.conditions) {
                Text(verbatim: conditions)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            if let note = checkin.note, !note.isEmpty {
                Text(verbatim: note)
                    .font(AppTypography.bodySmall)
            }
            ForEach(checkin.catches) { item in
                CatchSummaryRow(
                    speciesName: speciesStore.name(for: item.speciesID),
                    count: item.count,
                    weightGrams: item.weightGrams,
                    lengthMillimeters: item.lengthMillimeters,
                    released: item.released
                )
            }
            if !checkin.media.isEmpty {
                ReportPhotoStrip(media: checkin.media, urls: photoURLs)
            }
        }
        .cardContentPadding()
        .cardStyle()
    }
}

/// Поездка из очереди отправки в профиле.
struct PendingTripRow: View {
    let item: PendingTrip

    @Environment(SyncEngine.self) private var sync
    @State private var confirmsDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: item.activity.systemImage)
                    .foregroundStyle(AppColors.accent)
                Text(verbatim: item.title)
                    .font(AppTypography.bodyEmphasis)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(item.startedAt, style: .relative)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            switch item.state {
            case .waiting:
                Label("pending.waiting", systemImage: "icloud.and.arrow.up")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.warning)
            case .failed(let message):
                Label("pending.failed", systemImage: "exclamationmark.triangle.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.destructive)
                if !message.isEmpty {
                    Text(verbatim: message)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                HStack(spacing: AppSpacing.md) {
                    Button("common.retry") {
                        Task { await sync.retry(item.id) }
                    }
                    .secondaryButton()
                    Button("pending.discard", role: .destructive) {
                        confirmsDiscard = true
                    }
                    .secondaryButton()
                }
            }
        }
        .cardContentPadding()
        .cardStyle()
        .confirmationDialog("trip.pending.discardConfirm", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("pending.discard", role: .destructive) {
                Task { await sync.discard(item.id) }
            }
        }
    }
}
