import DaladaCore
import DesignComponents
import DesignTokens
import PhotosUI
import SwiftUI

/// Форма улова: вид, вес, длина, количество, фото, способ, приманка, отпущена, скрыть размер.
struct CatchFormView: View {
    /// Промысловая мера в месте улова: вид → см (подсказка, без блокировки).
    let minSizes: [String: Int]
    let onDone: @MainActor (CatchDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SpeciesStore.self) private var speciesStore
    @State private var draft: CatchDraft
    @State private var pickerItem: PhotosPickerItem?
    @State private var isProcessingPhoto = false
    @State private var photoFailed = false

    init(draft: CatchDraft, minSizes: [String: Int] = [:], onDone: @escaping @MainActor (CatchDraft) -> Void) {
        self.minSizes = minSizes
        self.onDone = onDone
        _draft = State(initialValue: draft)
    }

    /// Промысловая мера выбранного вида здесь, см.
    private var minSize: Int? { minSizes[draft.speciesID] }

    /// Длина меньше промысловой меры.
    private var isUndersized: Bool {
        guard let minSize, let length = draft.lengthCm else { return false }
        return length < Double(minSize)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("catch.form.species") {
                    Picker("catch.form.species", selection: $draft.speciesID) {
                        ForEach(speciesStore.species) { species in
                            Text(verbatim: species.name(for: SpeciesStore.languageCode)).tag(species.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    LabeledContent("catch.form.weight") {
                        TextField("catch.form.weightPlaceholder", value: $draft.weightKg, format: .number.precision(.fractionLength(0...3)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("catch.form.length") {
                        TextField("catch.form.lengthPlaceholder", value: $draft.lengthCm, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Stepper(value: $draft.count, in: 1...1000) {
                        LabeledContent("catch.form.count") {
                            Text(verbatim: "\(draft.count)")
                                .monospacedDigit()
                        }
                    }
                } footer: {
                    if let minSize, !isUndersized {
                        Text("rules.catch.minSizeHint \(minSize)")
                    }
                }

                if isUndersized, let minSize {
                    Section {
                        RecommendationBox(
                            text: String(localized: "rules.catch.undersized \(minSize)"),
                            color: AppColors.warning,
                            icon: "ruler"
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    if let photo = draft.photo {
                        HStack(spacing: AppSpacing.md) {
                            PhotoDraftThumbnail(photo: photo)
                            Spacer(minLength: 0)
                            Button("photo.remove", role: .destructive) {
                                draft.photo = nil
                            }
                            .buttonStyle(.borderless)
                        }
                    } else if isProcessingPhoto {
                        ProgressView()
                    } else {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("catch.form.addPhoto", systemImage: "camera")
                        }
                    }
                } header: {
                    Text("catch.form.photo")
                } footer: {
                    if photoFailed {
                        Text("photo.failed")
                            .foregroundStyle(AppColors.destructive)
                    }
                }

                Section {
                    Picker("catch.form.method", selection: $draft.method) {
                        Text("common.notSpecified").tag(FishingMethod?.none)
                        ForEach(FishingMethod.allCases) { method in
                            Text(LocalizedStringKey(method.titleKey)).tag(Optional(method))
                        }
                    }
                    TextField("catch.form.bait", text: $draft.bait)
                    Toggle("catch.form.released", isOn: $draft.released)
                    Toggle("catch.form.hideSize", isOn: $draft.hideSize)
                } footer: {
                    Text("catch.form.hideSizeFooter")
                }
            }
            .navigationTitle("catch.form.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        onDone(draft)
                        dismiss()
                    }
                    .disabled(!draft.isValid || isProcessingPhoto)
                }
            }
            .task { await speciesStore.loadIfNeeded() }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        pickerItem = nil
        isProcessingPhoto = true
        photoFailed = false
        defer { isProcessingPhoto = false }
        if let photo = await PhotoCompressor.draft(from: item) {
            draft.photo = photo
        } else {
            photoFailed = true
        }
    }
}
