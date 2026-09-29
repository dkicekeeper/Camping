import DaladaUI
import SwiftUI

/// Вкладка «Места» — заглушка до этапа M1.
struct PlacesHomeView: View {
    var body: some View {
        NavigationStack {
            PlaceholderScreen(
                icon: "mappin.and.ellipse",
                title: String(localized: "places.empty.title"),
                description: String(localized: "places.empty.description")
            )
            .navigationTitle("tab.places")
        }
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

#Preview("Места") { PlacesHomeView() }
#Preview("Лайфхаки") { LifehacksHomeView() }
