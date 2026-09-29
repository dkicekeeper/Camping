import DaladaCore
import DesignTokens
import SwiftUI

/// Форма улова: вид, вес, длина, количество, способ, приманка, отпущена, скрыть размер.
struct CatchFormView: View {
    let onDone: @MainActor (CatchDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SpeciesStore.self) private var speciesStore
    @State private var draft: CatchDraft

    init(draft: CatchDraft, onDone: @escaping @MainActor (CatchDraft) -> Void) {
        self.onDone = onDone
        _draft = State(initialValue: draft)
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
                    .disabled(!draft.isValid)
                }
            }
            .task { await speciesStore.loadIfNeeded() }
        }
    }
}
