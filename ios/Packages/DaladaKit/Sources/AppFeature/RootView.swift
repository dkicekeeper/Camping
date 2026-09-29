import DaladaCore
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
    @State private var selection: AppTab = .profile
    @State private var showsQuickActions = false

    public init(environment: AppEnvironment) {
        self.environment = environment
        _session = State(initialValue: SessionStore(backend: environment.backend, cache: environment.cache))
        _species = State(initialValue: SpeciesStore(backend: environment.backend, cache: environment.cache))
        let sender: any CheckinSending
        if let backend = environment.backend {
            sender = backend
        } else {
            sender = UnavailableSender()
        }
        _sync = State(initialValue: SyncEngine(outbox: environment.database.outbox, sender: sender))
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
        // «+» не открывает вкладку: возвращаем прежнюю и показываем быстрые действия.
        .onChange(of: selection) { previous, current in
            guard current == .quickAction else { return }
            selection = previous
            showsQuickActions = true
        }
        .sheet(isPresented: $showsQuickActions) {
            QuickActionsSheet()
                .presentationDetents([.medium])
        }
        // После первого входа — выбор username, пока он не сохранён.
        .fullScreenCover(isPresented: $session.isUsernameOnboardingPresented) {
            UsernameOnboardingView()
                .environment(session)
        }
        .environment(session)
        .environment(species)
        .environment(sync)
        .task { await session.start() }
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
}

#Preview {
    RootView(environment: .preview)
}
