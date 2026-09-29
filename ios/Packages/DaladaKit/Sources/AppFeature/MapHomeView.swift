import DaladaCore
import MapEngine
import SwiftUI

/// Вкладка «Карта». Пока — базовая карта Алматинского региона с позицией пользователя.
struct MapHomeView: View {
    let environment: AppEnvironment

    var body: some View {
        DaladaMapView(styleURL: environment.config.mapStyleURL, initialCenter: .almaty, initialZoom: 8)
            .ignoresSafeArea(edges: .top)
    }
}
