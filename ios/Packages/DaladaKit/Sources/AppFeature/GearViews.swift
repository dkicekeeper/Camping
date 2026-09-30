import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

// MARK: - Форматы

enum GearFormat {
    /// «750 г», «8,2 кг».
    static func weight(_ grams: Int) -> String {
        if grams >= 1000 {
            return Measurement(value: Double(grams) / 1000, unit: UnitMass.kilograms)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                        numberFormatStyle: .number.precision(.fractionLength(0...1))))
        }
        return Measurement(value: Double(grams), unit: UnitMass.grams)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }

    /// «14 предметов · 8,2 кг» (вес — если указан хоть у одного).
    static func summary(_ items: [GearItem]) -> String {
        let summary = GearCategorySummary.make(items)
        let count = summary.reduce(0) { $0 + $1.count }
        let grams = summary.reduce(0) { $0 + $1.weightGrams }
        let countText = String(localized: "gear.count \(count)")
        return grams > 0 ? countText + " · " + weight(grams) : countText
    }
}

// MARK: - Моя экипировка

/// «Моя экипировка»: предметы по категориям, сводка по количеству и весу, статусы.
struct GearListView: View {
    @Environment(ListsStore.self) private var lists
    @State private var editing: GearItem?
    @State private var addsPopular = false

    private var summaries: [GearCategorySummary] { GearCategorySummary.make(lists.gear) }

    var body: some View {
        List {
            if lists.gear.isEmpty {
                Section {
                    EmptyStateView(
                        icon: "backpack",
                        title: String(localized: "gear.empty.title"),
                        description: String(localized: "gear.empty.description"),
                        actionTitle: String(localized: "gear.addPopular"),
                        action: { addsPopular = true }
                    )
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    GearSummaryView(items: lists.gear)
                }

                ForEach(summaries) { summary in
                    Section {
                        ForEach(lists.gear.filter { $0.category == summary.category }) { item in
                            Button {
                                editing = item
                            } label: {
                                GearRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            let inCategory = lists.gear.filter { $0.category == summary.category }
                            for item in offsets.map({ inCategory[$0] }) {
                                lists.delete(item)
                            }
                        }
                    } header: {
                        GearCategoryHeader(
                            category: summary.category,
                            trailing: summary.weightGrams > 0 ? GearFormat.weight(summary.weightGrams) : nil
                        )
                    }
                }
            }
        }
        .navigationTitle("gear.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editing = GearItem(name: "")
                    } label: {
                        Label("gear.new", systemImage: "plus")
                    }
                    Button {
                        addsPopular = true
                    } label: {
                        Label("gear.addPopular", systemImage: "list.bullet.rectangle")
                    }
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel(Text("gear.new"))
                }
            }
        }
        .sheet(item: $editing) { item in
            GearFormView(item: item, isNew: lists.gearItem(item.id) == nil)
                .environment(lists)
        }
        .sheet(isPresented: $addsPopular) {
            PopularGearView()
                .environment(lists)
        }
        .task { await lists.loadTemplates() }
    }
}

/// Сводка: сколько предметов, общий вес, сколько в ремонте и что купить.
struct GearSummaryView: View {
    let items: [GearItem]

    private var repairCount: Int { items.filter { $0.status == .repair }.count }
    private var buyCount: Int { items.filter { $0.status == .buy }.count }
    private var hasUnknownWeight: Bool { items.contains { $0.weightGrams == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(verbatim: GearFormat.summary(items))
                .font(AppTypography.bodyEmphasis)
            if hasUnknownWeight {
                Text("gear.summary.unknownWeight")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            if repairCount > 0 || buyCount > 0 {
                HStack(spacing: AppSpacing.md) {
                    if repairCount > 0 {
                        Label("gear.summary.repair \(repairCount)", systemImage: GearStatus.repair.systemImage)
                            .foregroundStyle(AppColors.warning)
                    }
                    if buyCount > 0 {
                        Label("gear.summary.buy \(buyCount)", systemImage: GearStatus.buy.systemImage)
                            .foregroundStyle(AppColors.accent)
                    }
                }
                .font(AppTypography.caption)
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }
}

/// Предмет: название, бренд, количество, вес, статус (если не «в порядке»).
struct GearRow: View {
    let item: GearItem

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: item.name)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                if let details {
                    Text(verbatim: details)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if item.status != .ok {
                Label(LocalizedStringKey(item.status.titleKey), systemImage: item.status.systemImage)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(item.status == .repair ? AppColors.warning : AppColors.accent)
            }
        }
        .contentShape(Rectangle())
    }

    /// «Shimano · ×2 · 620 г».
    private var details: String? {
        var parts: [String] = []
        if let brand = item.brand { parts.append(brand) }
        if item.quantity > 1 { parts.append("×\(item.quantity)") }
        if let total = item.totalWeightGrams { parts.append(GearFormat.weight(total)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Предмет

/// Новый предмет или правка: название, категория, бренд, вес, количество, статус, заметка.
struct GearFormView: View {
    let isNew: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(ListsStore.self) private var lists
    @State private var draft: GearItem
    @State private var brand: String
    @State private var note: String
    @State private var confirmsDelete = false

    init(item: GearItem, isNew: Bool) {
        self.isNew = isNew
        _draft = State(initialValue: item)
        _brand = State(initialValue: item.brand ?? "")
        _note = State(initialValue: item.note ?? "")
    }

    private var edited: GearItem {
        var item = draft
        item.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.note = note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return item
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("gear.form.name", text: $draft.name)
                    Picker("gear.form.category", selection: $draft.category) {
                        ForEach(GearCategory.allCases) { category in
                            Label(LocalizedStringKey(category.titleKey), systemImage: category.systemImage)
                                .tag(category)
                        }
                    }
                    TextField("gear.form.brand", text: $brand)
                }

                Section {
                    LabeledContent("gear.form.weight") {
                        TextField("gear.form.weightPlaceholder", value: $draft.weightGrams, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Stepper(value: $draft.quantity, in: 1...999) {
                        LabeledContent("gear.form.quantity") {
                            Text(verbatim: "\(draft.quantity)")
                                .monospacedDigit()
                        }
                    }
                } footer: {
                    Text("gear.form.weightFooter")
                }

                Section {
                    Picker("gear.form.status", selection: $draft.status) {
                        ForEach(GearStatus.allCases) { status in
                            Text(LocalizedStringKey(status.titleKey)).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("gear.form.status")
                }

                Section("gear.form.note") {
                    TextField("gear.form.notePlaceholder", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }

                if !isNew {
                    Section {
                        Button("gear.delete", role: .destructive) {
                            confirmsDelete = true
                        }
                    }
                }
            }
            .navigationTitle(isNew ? Text("gear.new") : Text(verbatim: draft.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        lists.save(edited)
                        dismiss()
                    }
                    .disabled(!edited.isValid)
                }
            }
            .confirmationDialog("gear.deleteConfirm", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("gear.delete", role: .destructive) {
                    lists.delete(draft)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Быстрое добавление

/// Популярные предметы из шаблонов редакции: отметить нужные и добавить разом.
struct PopularGearView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ListsStore.self) private var lists
    @State private var selected: Set<String> = []

    private var items: [ChecklistTemplate.Item] { ChecklistTemplate.popularItems(lists.templates) }

    /// Уже есть в экипировке (по названию).
    private var owned: Set<String> { Set(lists.gear.map { $0.name.lowercased() }) }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text("checklists.templates.unavailable")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                ForEach(GearCategory.allCases) { category in
                    let inCategory = items.filter { $0.category == category }
                    if !inCategory.isEmpty {
                        Section {
                            ForEach(inCategory) { item in
                                row(item)
                            }
                        } header: {
                            GearCategoryHeader(category: category)
                        }
                    }
                }
            }
            .navigationTitle("gear.addPopular")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("gear.addSelected \(selected.count)") {
                        lists.addPopular(items.filter { selected.contains($0.id) }, language: PackingFormat.language)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .task { await lists.loadTemplates() }
        }
    }

    private func row(_ item: ChecklistTemplate.Item) -> some View {
        let title = item.title.text(for: PackingFormat.language)
        let isOwned = owned.contains(title.lowercased())
        let isSelected = selected.contains(item.id)
        return Button {
            if isSelected {
                selected.remove(item.id)
            } else {
                selected.insert(item.id)
            }
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: isOwned || isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOwned ? AppColors.textTertiary : isSelected ? AppColors.accent : AppColors.textTertiary)
                Text(verbatim: title)
                    .foregroundStyle(isOwned ? AppColors.textSecondary : AppColors.textPrimary)
                Spacer(minLength: 0)
                if isOwned {
                    Text("gear.popular.owned")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOwned)
    }
}

/// Выбор предметов своей экипировки для чеклиста.
struct GearPickerView: View {
    /// Уже есть в чеклисте.
    let excluded: Set<UUID>
    let onPick: @MainActor ([GearItem]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ListsStore.self) private var lists
    @State private var selected: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(GearCategorySummary.make(lists.gear)) { summary in
                    Section {
                        ForEach(lists.gear.filter { $0.category == summary.category }) { item in
                            row(item)
                        }
                    } header: {
                        GearCategoryHeader(category: summary.category)
                    }
                }
            }
            .navigationTitle("checklist.addFromGear")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("gear.addSelected \(selected.count)") {
                        onPick(lists.gear.filter { selected.contains($0.id) })
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func row(_ item: GearItem) -> some View {
        let isAdded = excluded.contains(item.id)
        let isSelected = selected.contains(item.id)
        return Button {
            if isSelected {
                selected.remove(item.id)
            } else {
                selected.insert(item.id)
            }
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: isAdded || isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textTertiary)
                GearRow(item: item)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
    }
}
