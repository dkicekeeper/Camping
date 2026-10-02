import DaladaCore
import DesignTokens
import MapEngine
import SwiftUI

/// Зона правил, открытая с карты — для `.sheet(item:)`.
struct RuleZoneSelection: Identifiable, Hashable {
    let id: String
}

/// Вкладка «Карта»: места в видимой области, карточка по тапу, новое место долгим нажатием
/// или кнопкой «Место», зоны запретов (цвет — действует сейчас, скоро или нет), «Начать поездку».
struct MapHomeView: View {
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @Environment(RulesStore.self) private var rules
    @Environment(TripRecorder.self) private var recorder
    @AppStorage("map.showsRules") private var showsRules = true
    @State private var model: MapScreenModel
    @State private var showsSignInHint = false
    @State private var selectedZone: RuleZoneSelection?

    init(environment: AppEnvironment) {
        self.environment = environment
        _model = State(initialValue: MapScreenModel(backend: environment.backend, cache: environment.cache))
    }

    var body: some View {
        DaladaMapView(
            styleURL: environment.config.mapStyleURL,
            initialCenter: .almaty,
            initialZoom: 8,
            places: model.mapPlaces,
            draftPin: model.newPlace?.coordinate,
            ruleAreas: showsRules ? rules.mapAreas() : [],
            onRegionChange: { model.visibleAreaChanged($0, viewer: session.profile?.id) },
            onPlaceTap: { model.selectedPlace = PlaceSelection(id: $0) },
            onRuleAreaTap: { selectedZone = RuleZoneSelection(id: $0) },
            onLongPress: { startNewPlace(at: $0) }
        )
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topLeading) {
            Button {
                showsRules.toggle()
            } label: {
                Label("map.rules", systemImage: showsRules ? "exclamationmark.shield.fill" : "exclamationmark.shield")
                    .font(AppTypography.bodyEmphasis)
            }
            .secondaryButton()
            .accessibilityAddTraits(showsRules ? .isSelected : [])
            .padding(.leading, AppSpacing.lg)
            .padding(.top, AppSpacing.sm)
        }
        .sheet(item: $selectedZone) { selection in
            NavigationStack {
                RuleZoneView(zoneID: selection.id, environment: environment)
            }
            .presentationDetents([.medium, .large])
        }
        .task { await rules.loadIfNeeded() }
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
        // Во время записи вместо кнопки — мини-плеер над вкладками (где он есть).
        .overlay(alignment: .bottom) {
            if !recorder.isActive || !TripAccessoryModifier.isAvailable {
                StartTripButton()
                    .font(AppTypography.bodyEmphasis)
                    .primaryButton()
                    .padding(.bottom, AppSpacing.lg)
            }
        }
        .sheet(item: $model.selectedPlace) { selection in
            PlaceCardView(placeID: selection.id, environment: environment)
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
