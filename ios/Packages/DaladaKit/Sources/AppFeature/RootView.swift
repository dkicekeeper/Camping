import DaladaCore
import DaladaUI
import DesignComponents
import SwiftUI
import Sync

/// Вкладки приложения. `quickAction` — не экран, а кнопка «+» с быстрыми действиями.
enum AppTab: Hashable {
    case profile
    case map
    case places
    case lifehacks
    case quickAction
}

/// Корень приложения: четыре вкладки и «+» (docs/02-plan/README.md, «Информационная архитектура»).
public struct RootView: View {
    private let environment: AppEnvironment
    private let background: BackgroundSync

    @Environment(\.scenePhase) private var scenePhase
    @State private var session: SessionStore
    @State private var species: SpeciesStore
    @State private var sync: SyncEngine
    @State private var recorder: TripRecorder
    @State private var reactions: ReactionStore
    @State private var rules: RulesStore
    @State private var lists: ListsStore
    @State private var articles: ArticlesStore
    @State private var places: PlacesStore
    @State private var selection: AppTab = .profile
    /// Знакомство при первом запуске пройдено (или пропущено).
    @AppStorage("intro.completed") private var introCompleted = false
    @State private var showsQuickActions = false
    @State private var showsRecording = false
    /// Выбор из «+», который выполняется, когда лист «+» закроется.
    @State private var pendingTripActivity: TripActivity?
    @State private var opensRecordingAfterSheet = false
    /// Открытая ссылка-приглашение `dalada://u/<username>`.
    @State private var profileLink: ProfileLink?
    /// Обсуждение из пуша `dalada://thread/<id>`.
    @State private var threadLink: ThreadLinkItem?

    public init(environment: AppEnvironment, background: BackgroundSync) {
        self.environment = environment
        self.background = background
        _session = State(initialValue: SessionStore(
            backend: environment.backend, cache: environment.cache, database: environment.database
        ))
        _species = State(initialValue: SpeciesStore(backend: environment.backend, cache: environment.cache))
        _sync = State(initialValue: background.engine)
        _recorder = State(initialValue: TripRecorder(store: environment.database.trips))
        _reactions = State(initialValue: ReactionStore(backend: environment.backend))
        _rules = State(initialValue: RulesStore(backend: environment.backend, cache: environment.cache))
        _lists = State(initialValue: ListsStore(
            backend: environment.backend, database: environment.database, cache: environment.cache
        ))
        _articles = State(initialValue: ArticlesStore(backend: environment.backend, cache: environment.cache))
        _places = State(initialValue: PlacesStore(backend: environment.backend, cache: environment.cache))
    }

    public var body: some View {
        TabView(selection: $selection) {
            Tab("tab.profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                ProfileHomeView(environment: environment)
            }
            Tab("tab.map", systemImage: "map", value: AppTab.map) {
                MapHomeView(environment: environment)
            }
            Tab("tab.places", systemImage: "mappin.and.ellipse", value: AppTab.places) {
                PlacesHomeView(environment: environment)
            }
            Tab("tab.lifehacks", systemImage: "lightbulb", value: AppTab.lifehacks) {
                LifehacksHomeView(environment: environment)
            }
            Tab(value: AppTab.quickAction) {
                Color.clear
            } label: {
                PlusTabLabel(isExpanded: showsQuickActions)
            }
        }
        // Идущая запись поездки — мини-плеер над вкладками.
        .modifier(TripAccessoryModifier(isEnabled: recorder.isActive) { showsRecording = true })
        // Знакомство — поверх вкладок, один раз; вход отсюда открывает согласие и username.
        .overlay {
            if !introCompleted {
                IntroOnboardingView(environment: environment) {
                    withAnimation { introCompleted = true }
                }
                .transition(.opacity)
            }
        }
        // «+» не открывает вкладку: возвращаем прежнюю и показываем быстрые действия.
        .onChange(of: selection) { previous, current in
            guard current == .quickAction else { return }
            selection = previous
            showsQuickActions = true
        }
        .sheet(isPresented: $showsQuickActions, onDismiss: runPendingQuickAction) {
            QuickActionsSheet(
                isRecording: recorder.isActive,
                canRecord: session.profile != nil,
                onStartTrip: { pendingTripActivity = $0 },
                onOpenRecording: { opensRecordingAfterSheet = true }
            )
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showsRecording) {
            TripRecordingView(environment: environment)
                .environment(recorder)
                .environment(session)
                .environment(sync)
                .environment(species)
                .environment(reactions)
                .environment(rules)
        }
        // Ссылка-приглашение из QR-кода или сообщения — профиль человека.
        .onOpenURL { url in
            if let username = InviteLink.username(from: url) {
                profileLink = ProfileLink(username: username)
            } else if let threadID = ThreadLink.threadID(from: url) {
                threadLink = ThreadLinkItem(id: threadID)
            }
        }
        .sheet(item: $threadLink) { link in
            NavigationStack {
                ThreadView(threadID: link.id, environment: environment)
            }
            .environment(session)
            .environment(reactions)
        }
        .sheet(item: $profileLink) { link in
            NavigationStack {
                if session.profile != nil {
                    UserProfileView(username: link.username, environment: environment)
                } else {
                    PlaceholderScreen(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "@" + link.username,
                        description: String(localized: "invite.signInToAdd")
                    )
                }
            }
            .environment(session)
            .environment(species)
            .environment(sync)
            .environment(reactions)
            .environment(rules)
        }
        // После первого входа — согласие с условиями, затем выбор username.
        .fullScreenCover(isPresented: $session.isOnboardingPresented) {
            Group {
                if session.needsConsent {
                    ConsentView()
                } else {
                    UsernameOnboardingView()
                }
            }
            .environment(session)
        }
        .environment(session)
        .environment(species)
        .environment(sync)
        .environment(recorder)
        .environment(reactions)
        .environment(rules)
        .environment(lists)
        .environment(articles)
        .environment(places)
        .task { await session.start() }
        // Правила нужны без сети (карта, форма улова): сохранённая копия и обновление.
        .task { await rules.loadIfNeeded() }
        // Незаконченная запись поездки (приложение закрыли или система выгрузила) продолжается.
        .task { await recorder.restore() }
        // Офлайн-очередь: отправляем при появлении сети, возврате в приложение и входе.
        .task {
            for await _ in NetworkMonitor.becameAvailable() {
                sync.kick(force: true)
                lists.scheduleSync(after: .zero)
                Task { await PushRegistrar.shared.update(userID: session.profile?.id, backend: environment.backend) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                sync.kick(force: true)
                lists.scheduleSync(after: .zero)
                // Разрешение на уведомления могли дать в Настройках.
                Task { await PushRegistrar.shared.update(userID: session.profile?.id, backend: environment.backend) }
            case .background:
                background.didEnterBackground()
            default:
                break
            }
        }
        .onChange(of: session.profile?.id, initial: true) { previous, current in
            Task {
                await sync.refresh()
                sync.kick(force: true)
            }
            // Экипировка и чеклисты: свои у каждого аккаунта, у гостя — на телефоне.
            Task { await lists.switchUser(from: previous, to: current) }
            // Пуши: телефон получает уведомления вошедшего аккаунта (если разрешены).
            Task { await PushRegistrar.shared.update(userID: current, backend: environment.backend) }
        }
    }

    /// Действие из «+» выполняется после закрытия листа: иначе полноэкранная запись
    /// не откроется поверх закрывающегося листа.
    private func runPendingQuickAction() {
        if let activity = pendingTripActivity {
            pendingTripActivity = nil
            Task {
                await recorder.start(activity: activity)
                showsRecording = true
            }
        } else if opensRecordingAfterSheet {
            opensRecordingAfterSheet = false
            showsRecording = true
        }
    }
}

#Preview {
    RootView(environment: .preview, background: BackgroundSync(environment: .preview))
}

/// Обсуждение, открытое по ссылке из пуша.
struct ThreadLinkItem: Identifiable, Hashable {
    let id: UUID
}
