import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

// MARK: - Сводка отчётов

/// «За 7 дней: 12 отчётов, клёв в основном хороший».
struct PlaceReportsSummaryView: View {
    let summary: PlaceReportsSummary

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "chart.bar.xaxis")
        }
        .font(AppTypography.bodySmall)
        .foregroundStyle(AppColors.textSecondary)
    }

    private var text: String {
        let count = summary.isLowerBound
            ? String(localized: "place.summary.reportsAtLeast \(summary.count)")
            : String(localized: "place.summary.reports \(summary.count)")
        guard let bite = summary.bite else { return count }
        return count + ", " + String(localized: String.LocalizationValue("place.summary.bite.\(bite.rawValue)"))
    }
}

// MARK: - «Информация»

/// Атрибуты места: рыба, способы ловли, подъезд, стоимость, удобства, связь, сезон, особенности.
/// Своё место — «Изменить»; чужое публичное — «Предложить правку» и «Сообщить о проблеме».
struct PlaceInfoSection: View {
    let place: PlaceDetails
    let canEdit: Bool
    let canSuggest: Bool
    /// Мои предложения к месту, которые ещё на проверке.
    let pendingSuggestions: Set<PlaceSuggestionKind>
    let onEdit: () -> Void
    let onSuggest: (PlaceSuggestionKind) -> Void

    @Environment(SpeciesStore.self) private var speciesStore

    private var info: PlaceAttributes { place.info.normalized }

    var body: some View {
        if !info.isEmpty || canEdit || canSuggest {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeaderView(String(localized: "place.info.title"), systemImage: "info.circle")
                if info.isEmpty {
                    Text(LocalizedStringKey(canEdit ? "place.info.empty.own" : "place.info.empty"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ForEach(rows, id: \.titleKey) { row in
                            PlaceInfoRow(row: row)
                        }
                    }
                    .cardContentPadding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
                actions
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if canEdit {
            Button(action: onEdit) {
                Label(LocalizedStringKey(info.isEmpty ? "place.info.add" : "place.info.edit"), systemImage: "square.and.pencil")
                    .font(AppTypography.bodySmall)
            }
        } else if canSuggest {
            HStack(spacing: AppSpacing.lg) {
                Button {
                    onSuggest(.edit)
                } label: {
                    Label("place.suggest.edit", systemImage: "square.and.pencil")
                }
                Menu {
                    ForEach(PlaceSuggestionKind.problems) { kind in
                        Button(LocalizedStringKey(kind.titleKey)) { onSuggest(kind) }
                    }
                } label: {
                    Label("place.suggest.problem", systemImage: "exclamationmark.bubble")
                }
            }
            .font(AppTypography.bodySmall)
            if !pendingSuggestions.isEmpty {
                Label("place.suggest.pending", systemImage: "hourglass")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    /// Строки по порядку: у мест для рыбалки сначала рыба и способы ловли.
    private var rows: [PlaceInfoRow.Model] {
        var fishing: [PlaceInfoRow.Model] = []
        if !info.species.isEmpty {
            fishing.append(.init(titleKey: "place.info.species", systemImage: "fish", value: speciesText))
        }
        if !info.methods.isEmpty {
            fishing.append(.init(
                titleKey: "place.info.methods",
                systemImage: "figure.fishing",
                value: Self.titles(PlaceAttributes.Method.allCases.filter(info.methods.contains), \.titleKey)
            ))
        }
        var other: [PlaceInfoRow.Model] = []
        if !info.access.isEmpty {
            other.append(.init(
                titleKey: "place.info.access",
                systemImage: "car",
                value: Self.titles(PlaceAttributes.Access.allCases.filter(info.access.contains), \.titleKey)
            ))
        }
        if let fee = feeText {
            other.append(.init(titleKey: "place.info.fee", systemImage: "banknote", value: fee))
        }
        if let contact = info.contact {
            other.append(.init(titleKey: "place.info.contact", systemImage: "phone", value: contact, isSelectable: true))
        }
        if !info.amenities.isEmpty {
            other.append(.init(
                titleKey: "place.info.amenities",
                systemImage: "checklist",
                value: Self.titles(PlaceAttributes.Amenity.allCases.filter(info.amenities.contains), \.titleKey)
            ))
        }
        if let signal = info.signal {
            other.append(.init(
                titleKey: "place.info.signal",
                systemImage: "antenna.radiowaves.left.and.right",
                value: String(localized: String.LocalizationValue(signal.titleKey))
            ))
        }
        if !info.months.isEmpty {
            other.append(.init(titleKey: "place.info.months", systemImage: "calendar", value: monthsText))
        }
        if let features = info.features {
            other.append(.init(titleKey: "place.info.features", systemImage: "text.alignleft", value: features))
        }
        return place.type.isFishing ? fishing + other : other + fishing
    }

    private var speciesText: String {
        let order = Dictionary(uniqueKeysWithValues: speciesStore.species.map { ($0.id, $0.sortOrder) })
        return info.species
            .sorted { (order[$0] ?? .max) < (order[$1] ?? .max) }
            .map { speciesStore.name(for: $0) }
            .joined(separator: ", ")
    }

    private var feeText: String? {
        guard let fee = info.fee else { return nil }
        var parts = [String(localized: String.LocalizationValue(fee.titleKey))]
        if let price = info.priceKZT {
            var priceText = price.formatted(.number) + " ₸"
            if let unit = info.priceUnit {
                priceText += " " + String(localized: String.LocalizationValue(unit.titleKey))
            }
            parts.append(priceText)
        }
        return parts.joined(separator: " · ")
    }

    private var monthsText: String {
        let symbols = PlaceMonths.names
        let text = PlaceAttributes.monthSpans(info.months)
            .map { span in
                span.from == span.to ? symbols[span.from - 1] : symbols[span.from - 1] + "–" + symbols[span.to - 1]
            }
            .joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func titles<T>(_ values: [T], _ key: KeyPath<T, String>) -> String {
        values.map { String(localized: String.LocalizationValue($0[keyPath: key])) }.joined(separator: ", ")
    }
}

/// Строка «Информации»: значок, подпись, значение.
private struct PlaceInfoRow: View {
    struct Model {
        let titleKey: String
        let systemImage: String
        let value: String
        var isSelectable = false
    }

    let row: Model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Image(systemName: row.systemImage)
                .foregroundStyle(AppColors.accent)
                .frame(width: AppIconSize.md)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(LocalizedStringKey(row.titleKey))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                if row.isSelectable {
                    Text(verbatim: row.value)
                        .font(AppTypography.bodySmall)
                        .textSelection(.enabled)
                } else {
                    Text(verbatim: row.value)
                        .font(AppTypography.bodySmall)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Названия месяцев на языке интерфейса (по-русски и по-казахски — со строчной).
enum PlaceMonths {
    static var names: [String] { formatter.standaloneMonthSymbols }

    static var shortNames: [String] {
        formatter.shortStandaloneMonthSymbols.map { $0.trimmingCharacters(in: .punctuationCharacters) }
    }

    private static var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppConfig.interfaceLanguage)
        return formatter
    }
}

// MARK: - Поля «Информации» в формах

extension PlaceAttributes.Access: TitledOption {}
extension PlaceAttributes.Fee: TitledOption {}
extension PlaceAttributes.PriceUnit: TitledOption {}
extension PlaceAttributes.Method: TitledOption {}
extension PlaceAttributes.Amenity: TitledOption {}
extension PlaceAttributes.Signal: TitledOption {}

/// Поля атрибутов в форме: своё место и предложение правки. Короткие списки — чипами, рыба —
/// отдельным списком.
struct PlaceAttributesFields: View {
    @Binding var attributes: PlaceAttributes
    let type: PlaceType

    @Environment(SpeciesStore.self) private var speciesStore

    var body: some View {
        Section {
            if type.isFishing {
                fishing
            }
            ChipPicker(
                String(localized: "place.info.access"),
                options: PlaceAttributes.Access.allCases,
                selection: $attributes.access
            ) { $0.title }
            ChipPicker(
                String(localized: "place.info.amenities"),
                options: PlaceAttributes.Amenity.allCases,
                selection: $attributes.amenities,
                systemImage: { $0.systemImage }
            ) { $0.title }
            ChipPicker(
                String(localized: "place.info.signal"),
                options: PlaceAttributes.Signal.allCases,
                selection: $attributes.signal
            ) { $0.title }
            ChipPicker(
                String(localized: "place.info.months"),
                options: Array(1...12),
                selection: $attributes.months
            ) { PlaceMonths.shortNames[$0 - 1] }
            if !type.isFishing {
                fishing
            }
        } header: {
            Text("place.info.title")
        }

        Section {
            ChipPicker(options: PlaceAttributes.Fee.allCases, selection: $attributes.fee) { $0.title }
            if attributes.fee == .paid {
                HStack {
                    TextField("place.info.price", text: priceText)
                        .keyboardType(.numberPad)
                    Text(verbatim: "₸")
                        .foregroundStyle(AppColors.textSecondary)
                }
                ChipPicker(options: PlaceAttributes.PriceUnit.allCases, selection: $attributes.priceUnit) { $0.title }
            }
            TextField("place.info.contact.placeholder", text: text(\.contact))
                .textContentType(.telephoneNumber)
        } header: {
            Text("place.info.fee")
        } footer: {
            if (attributes.contact?.count ?? 0) > PlaceAttributes.contactLimit {
                Text("place.info.tooLong \(PlaceAttributes.contactLimit)")
                    .foregroundStyle(AppColors.destructive)
            }
        }

        Section {
            TextField("place.info.features.placeholder", text: text(\.features), axis: .vertical)
                .lineLimit(2...6)
        } header: {
            Text("place.info.features")
        } footer: {
            if (attributes.features?.count ?? 0) > PlaceAttributes.featuresLimit {
                Text("place.info.tooLong \(PlaceAttributes.featuresLimit)")
                    .foregroundStyle(AppColors.destructive)
            }
        }
    }

    /// Рыба (списком — видов много) и способы ловли.
    @ViewBuilder
    private var fishing: some View {
        NavigationLink {
            SpeciesSelectList(
                species: speciesStore.species.sorted { $0.sortOrder < $1.sortOrder },
                selection: Binding(
                    get: { Set(attributes.species) },
                    set: { selected in
                        let order = Dictionary(uniqueKeysWithValues: speciesStore.species.map { ($0.id, $0.sortOrder) })
                        attributes.species = selected.sorted { (order[$0] ?? .max) < (order[$1] ?? .max) }
                    }
                )
            )
        } label: {
            LabeledContent {
                if attributes.species.isEmpty {
                    Text("common.notSpecified")
                } else {
                    Text(verbatim: "\(attributes.species.count)")
                }
            } label: {
                Text("place.info.species")
            }
        }
        ChipPicker(
            String(localized: "place.info.methods"),
            options: PlaceAttributes.Method.allCases,
            selection: $attributes.methods
        ) { $0.title }
    }

    private var priceText: Binding<String> {
        Binding(
            get: { attributes.priceKZT.map(String.init) ?? "" },
            set: { value in
                let digits = String(value.filter(\.isASCIIDigit).prefix(7))
                attributes.priceKZT = Int(digits)
            }
        )
    }

    private func text(_ keyPath: WritableKeyPath<PlaceAttributes, String?>) -> Binding<String> {
        Binding(
            get: { attributes[keyPath: keyPath] ?? "" },
            set: { attributes[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

/// Виды рыбы места: выбрать несколько.
private struct SpeciesSelectList: View {
    let species: [FishSpecies]
    @Binding var selection: Set<String>

    var body: some View {
        List(species) { item in
            let isSelected = selection.contains(item.id)
            Button {
                if isSelected {
                    selection.remove(item.id)
                } else {
                    selection.insert(item.id)
                }
            } label: {
                HStack(spacing: AppSpacing.md) {
                    SelectionIndicator(isSelected: isSelected)
                    Text(verbatim: item.name(for: SpeciesStore.languageCode))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .navigationTitle("place.info.species")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Своё место: изменить

/// Изменить своё место: название, тип, описание, «Информация», видимость. Точку пока не двигаем.
struct PlaceEditView: View {
    let placeID: UUID
    let environment: AppEnvironment
    let onSaved: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: OwnPlaceDraft?
    @State private var original: OwnPlaceDraft?
    @State private var loadError: String?
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let draft = Binding($draft) {
                    form(draft)
                } else if let loadError {
                    EmptyStateView(
                        icon: "wifi.slash",
                        title: String(localized: "place.card.failed"),
                        description: loadError,
                        actionTitle: String(localized: "common.retry"),
                        action: { Task { await load() } },
                        style: .error
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("place.edit.title")
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
                        .disabled(draft == nil || draft == original || draft?.isValid != true)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving || (draft != nil && draft != original))
        }
        .task { await load() }
    }

    private func form(_ draft: Binding<OwnPlaceDraft>) -> some View {
        Form {
            Section {
                TextField("place.form.name", text: draft.fields.name)
                Picker("place.form.type", selection: draft.fields.type) {
                    ForEach(PlaceType.allCases) { type in
                        Label(LocalizedStringKey(type.titleKey), systemImage: type.systemImage)
                            .tag(type)
                    }
                }
            }

            Section("place.form.description") {
                TextField("place.form.descriptionPlaceholder", text: draft.fields.description, axis: .vertical)
                    .lineLimit(3...8)
            }

            PlaceAttributesFields(attributes: draft.fields.attributes, type: draft.wrappedValue.fields.type)

            Section {
                Picker("place.form.visibility", selection: draft.visibility) {
                    ForEach(Visibility.allCases) { visibility in
                        Text(LocalizedStringKey(visibility.titleKey)).tag(visibility)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("place.form.approximate", isOn: draft.isApproximate)
                    .disabled(draft.wrappedValue.visibility == .private)
            } header: {
                Text("place.form.visibility")
            } footer: {
                Text(PlaceFormView.visibilityFooter(
                    draft.wrappedValue.visibility,
                    approximate: draft.wrappedValue.effectiveApproximate
                ))
            }

            if let saveError {
                Section {
                    Text(verbatim: saveError)
                        .foregroundStyle(AppColors.destructive)
                }
            }
        }
    }

    private func load() async {
        guard let backend = environment.backend else {
            loadError = String(localized: "backend.status.notConfigured")
            return
        }
        loadError = nil
        do {
            if let loaded = try await backend.ownPlace(id: placeID) {
                original = loaded
                draft = loaded
            } else {
                loadError = String(localized: "place.card.notFound.description")
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() async {
        guard let draft, let backend = environment.backend else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await backend.updatePlace(id: placeID, draft)
            onSaved()
            dismiss()
        } catch {
            saveError = CommunityMessage.text(for: error)
        }
    }
}

// MARK: - Чужое место: предложить правку, сообщить о проблеме

/// Предложение к чужому публичному месту: правка полей или проблема (не та точка, закрыто, не
/// существует, дубль, опасно). Разбирает редакция.
struct PlaceSuggestView: View {
    let place: PlaceDetails
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var kind: PlaceSuggestionKind
    @State private var draft: PlaceEditDraft
    @State private var note = ""
    @State private var isSending = false
    @State private var isSent = false
    @State private var sendError: String?

    private let original: PlaceEditDraft

    init(place: PlaceDetails, kind: PlaceSuggestionKind, environment: AppEnvironment) {
        self.place = place
        self.environment = environment
        let original = PlaceEditDraft(place: place)
        self.original = original
        _kind = State(initialValue: kind)
        _draft = State(initialValue: original)
    }

    private var changes: PlaceChanges { draft.changes(from: original) }

    private var canSend: Bool {
        guard note.count <= PlaceEditDraft.noteLimit else { return false }
        return kind == .edit ? !changes.isEmpty && draft.isValid : true
    }

    var body: some View {
        NavigationStack {
            Form {
                if isSent {
                    Section {
                        Label("place.suggest.sent", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
                        Text("place.suggest.sentDetail")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                } else {
                    if kind == .edit {
                        editFields
                    } else {
                        problemKinds
                    }

                    Section {
                        TextField("place.suggest.notePlaceholder", text: $note, axis: .vertical)
                            .lineLimit(2...6)
                    } header: {
                        Text("place.suggest.note")
                    } footer: {
                        Text("place.suggest.footer")
                    }

                    if let sendError {
                        Section {
                            Text(verbatim: sendError)
                                .foregroundStyle(AppColors.destructive)
                        }
                    }
                }
            }
            .navigationTitle(LocalizedStringKey(kind == .edit ? "place.suggest.edit" : "place.suggest.problem"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isSent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.done") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSending {
                            ProgressView()
                        } else {
                            Button("place.suggest.send") {
                                Task { await send() }
                            }
                            .disabled(!canSend)
                        }
                    }
                }
            }
            .interactiveDismissDisabled(isSending)
        }
    }

    @ViewBuilder
    private var editFields: some View {
        Section {
            TextField("place.form.name", text: $draft.name)
            Picker("place.form.type", selection: $draft.type) {
                ForEach(PlaceType.allCases) { type in
                    Label(LocalizedStringKey(type.titleKey), systemImage: type.systemImage)
                        .tag(type)
                }
            }
        } footer: {
            Text("place.suggest.editHint")
        }

        Section("place.form.description") {
            TextField("place.form.descriptionPlaceholder", text: $draft.description, axis: .vertical)
                .lineLimit(3...8)
        }

        PlaceAttributesFields(attributes: $draft.attributes, type: draft.type)
    }

    private var problemKinds: some View {
        Section {
            ForEach(PlaceSuggestionKind.problems) { option in
                Button {
                    kind = option
                } label: {
                    HStack {
                        Text(LocalizedStringKey(option.titleKey))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer(minLength: 0)
                        if kind == option {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppColors.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(kind == option ? .isSelected : [])
            }
        } header: {
            Text("place.suggest.problem.what")
        }
    }

    private func send() async {
        guard let backend = environment.backend else { return }
        isSending = true
        defer { isSending = false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await backend.suggestPlaceChange(
                placeID: place.id,
                kind: kind,
                changes: kind == .edit ? changes : nil,
                note: trimmed.isEmpty ? nil : trimmed
            )
            isSent = true
        } catch {
            sendError = CommunityMessage.text(for: error)
        }
    }
}

// MARK: - Рядом

/// «Рядом»: похожие места поблизости (до 30 км), ближайшие первыми.
struct NearbyPlacesSection: View {
    let place: PlaceDetails
    let environment: AppEnvironment
    let onSelect: (UUID) -> Void

    @State private var items: [PlaceItem] = []
    @State private var photoURLs: [String: URL] = [:]

    private static let radius = 30_000
    private static let count = 6

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    SectionHeaderView(String(localized: "place.nearby"), systemImage: "location.circle")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: AppSpacing.md) {
                            ForEach(items) { item in
                                Button {
                                    onSelect(item.id)
                                } label: {
                                    PlaceItemCard(item: item, photoURL: item.photoPath.flatMap { photoURLs[$0] })
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .task(id: place.id) { await load() }
    }

    private func load() async {
        guard let backend = environment.backend else { return }
        // Показанная точка места: у чужого приблизительного — смещённый центр, как на карте.
        let query = PlaceQuery(types: place.type.similarTypes, sort: .distance)
        guard let found = try? await backend.searchPlaces(query, near: place.coordinate, limit: Self.count + 1)
        else { return }
        let nearby = Array(
            found
                .filter { $0.id != place.id && ($0.distanceM ?? .max) <= Self.radius }
                .prefix(Self.count)
        )
        let paths = nearby.compactMap(\.photoPath)
        if !paths.isEmpty {
            photoURLs = (try? await backend.signedMediaURLs(paths: paths)) ?? [:]
        }
        items = nearby
    }
}
