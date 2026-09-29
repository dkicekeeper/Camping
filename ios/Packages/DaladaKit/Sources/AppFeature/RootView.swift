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

    @State private var selection: AppTab = .profile
    @State private var showsQuickActions = false

    public init(environment: AppEnvironment) {
        self.environment = environment
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
                PlacesHomeView()
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
    }
}

#Preview {
    RootView(environment: .preview)
}
