import DaladaCore
import DesignTokens
import MapEngine
import SwiftUI

/// Вкладка «Карта»: места в видимой области, карточка по тапу, новое место долгим нажатием
/// или кнопкой «+».
struct MapHomeView: View {
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @State private var model: MapScreenModel
    @State private var showsSignInHint = false

    init(environment: AppEnvironment) {
        self.environment = environment
        _model = State(initialValue: MapScreenModel(backend: environment.backend))
    }

    var body: some View {
        DaladaMapView(
            styleURL: environment.config.mapStyleURL,
            initialCenter: .almaty,
            initialZoom: 8,
            places: model.mapPlaces,
            draftPin: model.newPlace?.coordinate,
            onRegionChange: { model.visibleAreaChanged($0) },
            onPlaceTap: { model.selectedPlace = PlaceSelection(id: $0) },
            onLongPress: { startNewPlace(at: $0) }
        )
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topTrailing) {
            Button {
                startNewPlace(at: model.visibleCenter)
            } label: {
                Label("map.addPlace", systemImage: "plus")
                    .font(AppTypography.bodyEmphasis)
            }
            .secondaryButton()
            .padding(.trailing, AppSpacing.lg)
            .padding(.top, AppSpacing.sm)
        }
        .sheet(item: $model.selectedPlace) { selection in
            PlaceCardView(placeID: selection.id, backend: environment.backend)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $model.newPlace) { request in
            PlaceFormView(coordinate: request.coordinate) { draft in
                await model.create(draft)
            }
        }
        .alert("map.signInRequired.title", isPresented: $showsSignInHint) {
            Button("common.ok") {}
        } message: {
            Text("map.signInRequired.message")
        }
    }

    private func startNewPlace(at coordinate: GeoPoint) {
        guard session.profile != nil else {
            showsSignInHint = true
            return
        }
        model.newPlace = NewPlaceRequest(coordinate: coordinate)
    }
}
