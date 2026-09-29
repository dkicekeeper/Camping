import Backend
import DaladaCore
import DesignTokens
import SwiftUI

/// Чекин «Я здесь»: как клюёт, людность, вода, дорога, уловы, заметка, видимость.
/// Всё, кроме места, необязательно — чекин должен занимать 10 секунд.
struct CheckinFormView: View {
    let placeName: String
    let backend: BackendClient?
    let onSaved: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SpeciesStore.self) private var speciesStore
    @State private var draft: CheckinDraft
    @State private var editingCatch: CatchDraft?
    @State private var locationState: LocationState = .locating
    @State private var isSaving = false
    @State private var saveError: String?

    enum LocationState: Equatable {
        case locating
        case found
        case unavailable
    }

    init(placeID: UUID, placeName: String, backend: BackendClient?, onSaved: @escaping @MainActor () -> Void) {
        self.placeName = placeName
        self.backend = backend
        self.onSaved = onSaved
        _draft = State(initialValue: CheckinDraft(placeID: placeID))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ChipRow(title: "conditions.bite", options: CheckinConditions.Bite.allCases, selection: $draft.conditions.bite)
                    ChipRow(title: "conditions.crowd", options: CheckinConditions.Crowd.allCases, selection: $draft.conditions.crowd)
                    ChipRow(title: "conditions.water", options: CheckinConditions.Water.allCases, selection: $draft.conditions.water)
                    ChipRow(title: "conditions.road", options: CheckinConditions.Road.allCases, selection: $draft.conditions.road)
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
                                released: catchDraft.released
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
                        .disabled(!draft.isValid)
                    }
                }
            }
            .sheet(item: $editingCatch) { catchDraft in
                CatchFormView(draft: catchDraft) { updated in
                    if let index = draft.catches.firstIndex(where: { $0.id == updated.id }) {
                        draft.catches[index] = updated
                    } else {
                        draft.catches.append(updated)
                    }
                }
                .environment(speciesStore)
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

    private func save() async {
        guard let backend else {
            saveError = String(localized: "backend.status.notConfigured")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await backend.createCheckin(draft)
            onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// Строка выбора одного варианта чипами (повторный тап снимает выбор).
struct ChipRow<Option: Identifiable & Hashable>: View where Option: TitledOption {
    let title: LocalizedStringKey
    let options: [Option]
    @Binding var selection: Option?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(options) { option in
                        Button {
                            selection = selection == option ? nil : option
                        } label: {
                            Text(LocalizedStringKey(option.titleKey))
                        }
                        .buttonStyle(.plain)
                        .filterChipStyle(isSelected: selection == option)
                    }
                }
                .padding(.vertical, AppSpacing.xxs)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

/// Вариант с ключом названия в `Localizable.xcstrings`.
protocol TitledOption {
    var titleKey: String { get }
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

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "fish")
                .foregroundStyle(AppColors.accent)
            Text(verbatim: summary)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: 0)
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
