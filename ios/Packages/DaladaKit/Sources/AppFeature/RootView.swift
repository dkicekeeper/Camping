import DesignComponents
import SwiftUI

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

    @State private var session: SessionStore
    @State private var species: SpeciesStore
    @State private var selection: AppTab = .profile
    @State private var showsQuickActions = false

    public init(environment: AppEnvironment) {
        self.environment = environment
        _session = State(initialValue: SessionStore(backend: environment.backend))
        _species = State(initialValue: SpeciesStore(backend: environment.backend))
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
        .task { await session.start() }
    }
}

#Preview {
    RootView(environment: .preview)
}
