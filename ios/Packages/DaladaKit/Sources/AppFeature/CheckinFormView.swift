import DaladaCore
import DesignComponents
import DesignTokens
import PhotosUI
import SwiftUI
import Sync

/// Чекин «Я здесь»: как клюёт, людность, вода, дорога, уловы, фото, заметка, видимость.
/// Всё, кроме места, необязательно — чекин должен занимать 10 секунд.
/// Сохраняется в офлайн-очередь и уходит на сервер сразу или когда появится сеть.
struct CheckinFormView: View {
    let placeName: String
    /// Точка места — для подсказок о запретах и промысловой мере.
    let coordinate: GeoPoint?
    let onSaved: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SpeciesStore.self) private var speciesStore
    @Environment(RulesStore.self) private var rules
    @Environment(SyncEngine.self) private var sync
    @State private var draft: CheckinDraft
    @State private var editingCatch: CatchDraft?
    @State private var locationState: LocationState = .locating
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isProcessingPhotos = false
    @State private var photoFailed = false

    enum LocationState: Equatable {
        case locating
        case found
        case unavailable
    }

    init(placeID: UUID, placeName: String, coordinate: GeoPoint? = nil, onSaved: @escaping @MainActor () -> Void) {
        self.placeName = placeName
        self.coordinate = coordinate
        self.onSaved = onSaved
        _draft = State(initialValue: CheckinDraft(placeID: placeID))
    }

    /// Запреты, которые действуют здесь в день чекина (мягкое предупреждение, без блокировки).
    private var activeBans: [Regulation] {
        guard let coordinate, let pack = rules.pack else { return [] }
        return pack.activeBans(at: coordinate, on: CalendarDay(draft.at, calendar: RulesStore.almatyCalendar))
    }

    /// Промысловая мера в этом месте: вид → см.
    private var minSizes: [String: Int] {
        guard let coordinate, let pack = rules.pack else { return [:] }
        return pack.minSizes(at: coordinate)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !activeBans.isEmpty, let pack = rules.pack {
                    Section {
                        ForEach(activeBans) { ban in
                            RecommendationBox(
                                text: String(localized: "rules.checkin.banWarning \(ban.title.text(for: RulesStore.language)) \(RuleFormat.statusText(pack.status(of: ban, on: CalendarDay(draft.at, calendar: RulesStore.almatyCalendar))).lowercased())"),
                                color: AppColors.destructive,
                                icon: "nosign"
                            )
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    ChipPicker(String(localized: "conditions.bite"), options: CheckinConditions.Bite.allCases, selection: $draft.conditions.bite) { $0.title }
                    ChipPicker(String(localized: "conditions.crowd"), options: CheckinConditions.Crowd.allCases, selection: $draft.conditions.crowd) { $0.title }
                    ChipPicker(String(localized: "conditions.water"), options: CheckinConditions.Water.allCases, selection: $draft.conditions.water) { $0.title }
                    ChipPicker(String(localized: "conditions.road"), options: CheckinConditions.Road.allCases, selection: $draft.conditions.road) { $0.title }
                } header: {
                    Text("checkin.form.conditions")
                }

                Section("checkin.form.catches") {
                    ForEach(draft.catches) { catchDraft in
                        Button {
                            editingCatch = catchDraft
                        } label: {
                            CatchSummaryRow(
                                speciesName: speciesStore.name(for: catchDraft.speciesID),
                                count: catchDraft.count,
                                weightGrams: catchDraft.weightGrams,
                                lengthMillimeters: catchDraft.lengthMillimeters,
                                released: catchDraft.released,
                                hasPhoto: catchDraft.photo != nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { draft.catches.remove(atOffsets: $0) }

                    Button {
                        editingCatch = CatchDraft(speciesID: speciesStore.species.first?.id ?? "common_carp")
                    } label: {
                        Label("checkin.form.addCatch", systemImage: "plus.circle")
                    }
                }

                Section {
                    if !draft.photos.isEmpty {
                        PhotoDraftStrip(photos: draft.photos) { id in
                            draft.photos.removeAll { $0.id == id }
                        }
                    }
                    if isProcessingPhotos {
                        ProgressView()
                    } else if draft.photos.count < CheckinDraft.photoLimit {
                        PhotosPicker(
                            selection: $pickerItems,
                            maxSelectionCount: CheckinDraft.photoLimit - draft.photos.count,
                            matching: .images
                        ) {
                            Label("checkin.form.addPhotos", systemImage: "photo.on.rectangle.angled")
                        }
                    }
                } header: {
                    Text("checkin.form.photos")
                } footer: {
                    if photoFailed {
                        Text("photo.failed")
                            .foregroundStyle(AppColors.destructive)
                    } else {
                        Text("checkin.form.photosFooter")
                    }
                }

                Section("checkin.form.note") {
                    TextField("checkin.form.notePlaceholder", text: $draft.note, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    Picker("place.form.visibility", selection: $draft.visibility) {
                        ForEach(Visibility.allCases) { visibility in
                            Text(LocalizedStringKey(visibility.titleKey)).tag(visibility)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("place.form.visibility")
                } footer: {
                    locationFooter
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(AppColors.destructive)
                    }
                }
            }
            .navigationTitle(Text(verbatim: placeName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("checkin.form.save") {
                            Task { await save() }
                        }
                        .disabled(!draft.isValid || isProcessingPhotos)
                    }
                }
            }
            .sheet(item: $editingCatch) { catchDraft in
                CatchFormView(draft: catchDraft, minSizes: minSizes) { updated in
                    if let index = draft.catches.firstIndex(where: { $0.id == updated.id }) {
                        draft.catches[index] = updated
                    } else {
                        draft.catches.append(updated)
                    }
                }
                .environment(speciesStore)
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await addPhotos(items) }
            }
            .interactiveDismissDisabled(isSaving)
            .task { await locate() }
            .task { await speciesStore.loadIfNeeded() }
        }
    }

    @ViewBuilder
    private var locationFooter: some View {
        switch locationState {
        case .locating:
            Label("checkin.location.locating", systemImage: "location")
        case .found:
            Label("checkin.location.found", systemImage: "location.fill")
        case .unavailable:
            Label("checkin.location.unavailable", systemImage: "location.slash")
        }
    }

    private func locate() async {
        if let location = await DeviceLocation.current() {
            draft.deviceLocation = location
            locationState = .found
        } else {
            locationState = .unavailable
        }
    }

    /// Сжимает выбранные фото по одному и добавляет в чекин (не больше лимита).
    private func addPhotos(_ items: [PhotosPickerItem]) async {
        pickerItems = []
        isProcessingPhotos = true
        photoFailed = false
        defer { isProcessingPhotos = false }
        for item in items {
            guard draft.photos.count < CheckinDraft.photoLimit else { break }
            if let photo = await PhotoCompressor.draft(from: item) {
                draft.photos.append(photo)
            } else {
                photoFailed = true
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var checkin = draft
        checkin.at = Date()
        do {
            // Сохраняется на телефоне сразу; на сервер — когда получится.
            try await sync.submit(checkin, placeName: placeName)
            onSaved()
            dismiss()
            // Первый чекин — момент первой пользы: объясним, зачем уведомления.
            Task { await NotificationPrimer.shared.offer() }
        } catch {
            saveError = String(localized: "checkin.save.failed")
        }
    }
}

/// Варианты условий с ключом названия в `Localizable.xcstrings`.
protocol TitledOption {
    var titleKey: String { get }
}

extension TitledOption {
    /// Локализованное название для `ChipPicker`.
    var title: String { String(localized: String.LocalizationValue(titleKey)) }
}

extension CheckinConditions.Bite: TitledOption {}
extension CheckinConditions.Crowd: TitledOption {}
extension CheckinConditions.Water: TitledOption {}
extension CheckinConditions.Road: TitledOption {}

/// Краткая строка улова: «Щука ×2 · 2,5 кг · 65 см · отпущена».
struct CatchSummaryRow: View {
    let speciesName: String
    let count: Int
    let weightGrams: Int?
    let lengthMillimeters: Int?
    let released: Bool
    var hasPhoto = false

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "fish")
                .foregroundStyle(AppColors.accent)
            Text(verbatim: summary)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: 0)
            if hasPhoto {
                Image(systemName: "camera.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .accessibilityLabel(Text("catch.form.photo"))
            }
        }
        .contentShape(Rectangle())
    }

    private var summary: String {
        var parts = [count > 1 ? "\(speciesName) ×\(count)" : speciesName]
        if let weightGrams {
            parts.append(Measurement(value: Double(weightGrams) / 1000, unit: UnitMass.kilograms)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...2)))))
        }
        if let lengthMillimeters {
            parts.append(Measurement(value: Double(lengthMillimeters) / 10, unit: UnitLength.centimeters)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1)))))
        }
        if released {
            parts.append(String(localized: "catch.released"))
        }
        return parts.joined(separator: " · ")
    }
}
