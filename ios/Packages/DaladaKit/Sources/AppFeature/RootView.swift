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

    @Environment(\.scenePhase) private var scenePhase
    @State private var session: SessionStore
    @State private var species: SpeciesStore
    @State private var sync: SyncEngine
    @State private var recorder: TripRecorder
    @State private var reactions: ReactionStore
    @State private var selection: AppTab = .profile
    @State private var showsQuickActions = false
    @State private var showsRecording = false
    /// Выбор из «+», который выполняется, когда лист «+» закроется.
    @State private var pendingTripActivity: TripActivity?
    @State private var opensRecordingAfterSheet = false
    /// Открытая ссылка-приглашение `dalada://u/<username>`.
    @State private var profileLink: ProfileLink?

    public init(environment: AppEnvironment) {
        self.environment = environment
        _session = State(initialValue: SessionStore(backend: environment.backend, cache: environment.cache))
        _species = State(initialValue: SpeciesStore(backend: environment.backend, cache: environment.cache))
        let sender: any OutboxSending
        if let backend = environment.backend {
            sender = backend
        } else {
            sender = UnavailableSender()
        }
        _sync = State(initialValue: SyncEngine(outbox: environment.database.outbox, sender: sender))
        _recorder = State(initialValue: TripRecorder(store: environment.database.trips))
        _reactions = State(initialValue: ReactionStore(backend: environment.backend))
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
                LifehacksHomeView()
            }
            Tab(value: AppTab.quickAction) {
                Color.clear
            } label: {
                PlusTabLabel(isExpanded: showsQuickActions)
            }
        }
        // Идущая запись поездки — мини-плеер над вкладками.
        .modifier(TripAccessoryModifier(isEnabled: recorder.isActive) { showsRecording = true })
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
        }
        // Ссылка-приглашение из QR-кода или сообщения — профиль человека.
        .onOpenURL { url in
            if let username = InviteLink.username(from: url) {
                profileLink = ProfileLink(username: username)
            }
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
        }
        // После первого входа — выбор username, пока он не сохранён.
        .fullScreenCover(isPresented: $session.isUsernameOnboardingPresented) {
            UsernameOnboardingView()
                .environment(session)
        }
        .environment(session)
        .environment(species)
        .environment(sync)
        .environment(recorder)
        .environment(reactions)
        .task { await session.start() }
        // Незаконченная запись поездки (приложение закрыли или система выгрузила) продолжается.
        .task { await recorder.restore() }
        // Офлайн-очередь: отправляем при появлении сети, возврате в приложение и входе.
        .task {
            for await _ in NetworkMonitor.becameAvailable() {
                sync.kick(force: true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sync.kick(force: true) }
        }
        .onChange(of: session.profile?.id, initial: true) { _, _ in
            Task {
                await sync.refresh()
                sync.kick(force: true)
            }
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
    RootView(environment: .preview)
}
