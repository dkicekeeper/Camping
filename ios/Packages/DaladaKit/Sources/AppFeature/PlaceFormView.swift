import DaladaCore
import DesignTokens
import SwiftUI

/// Форма нового места: название, тип, описание, видимость, «приблизительно».
struct PlaceFormView: View {
    let onSave: @MainActor (PlaceDraft) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlaceDraft
    @State private var isSaving = false
    @State private var saveError: String?

    init(coordinate: GeoPoint, onSave: @escaping @MainActor (PlaceDraft) async -> String?) {
        self.onSave = onSave
        _draft = State(initialValue: PlaceDraft(coordinate: coordinate))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("place.form.name", text: $draft.name)
                    Picker("place.form.type", selection: $draft.type) {
                        ForEach(PlaceType.allCases) { type in
                            Label(LocalizedStringKey(type.titleKey), systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                }

                Section("place.form.description") {
                    TextField("place.form.descriptionPlaceholder", text: $draft.description, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    Picker("place.form.visibility", selection: $draft.visibility) {
                        ForEach(Visibility.allCases) { visibility in
                            Text(LocalizedStringKey(visibility.titleKey)).tag(visibility)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("place.form.approximate", isOn: $draft.isApproximate)
                        .disabled(draft.visibility == .private)
                } header: {
                    Text("place.form.visibility")
                } footer: {
                    Text(Self.visibilityFooter(draft.visibility, approximate: draft.effectiveApproximate))
                }

                Section {
                    LabeledContent("place.form.coordinates") {
                        Text(verbatim: String(format: "%.5f, %.5f", draft.coordinate.latitude, draft.coordinate.longitude))
                            .monospacedDigit()
                    }
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(AppColors.destructive)
                    }
                }
            }
            .navigationTitle("place.form.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("common.save") {
                            Task { await save() }
                        }
                        .disabled(!draft.isValid)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    /// Кто увидит место и как — под выбором видимости (новое место и правка своего).
    static func visibilityFooter(_ visibility: Visibility, approximate: Bool) -> String {
        switch (visibility, approximate) {
        case (.private, _):
            String(localized: "place.form.footer.private")
        case (.friends, false):
            String(localized: "place.form.footer.friends")
        case (.friends, true):
            String(localized: "place.form.footer.friendsApproximate")
        case (.public, false):
            String(localized: "place.form.footer.public")
        case (.public, true):
            String(localized: "place.form.footer.publicApproximate")
        }
    }

    private func save() async {
        isSaving = true
        saveError = await onSave(draft)
        isSaving = false
        // При успехе лист закрывает модель (сбрасывает запрос на новое место).
    }
}
