import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

// MARK: - Форматы

enum PackingFormat {
    /// «сб, 3 октября».
    static func tripDay(_ day: CalendarDay) -> String {
        day.date().formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
    }

    /// Минуты от полуночи → время на сегодня (для выбора времени).
    static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 20) * 60 + (parts.minute ?? 0)
    }

    /// «20:00».
    static func time(minutes: Int) -> String {
        date(minutes: minutes).formatted(date: .omitted, time: .shortened)
    }

    /// Язык шаблонов — язык интерфейса, иначе русский.
    @MainActor static var language: String { RulesStore.language }
}

// MARK: - Строки

/// Чеклист или сборы в списке: название, день поездки, прогресс «12 из 20».
struct ChecklistSummaryRow: View {
    let checklist: Checklist

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                Text(verbatim: checklist.title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: 0)
                if checklist.isComplete {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppColors.success)
                        .accessibilityLabel(Text("packing.complete"))
                }
            }
            if let day = checklist.tripDate {
                Label(PackingFormat.tripDay(day), systemImage: "calendar")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            if checklist.items.isEmpty {
                Text("checklist.empty")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                ProgressView(value: checklist.progress)
                    .tint(checklist.isComplete ? AppColors.success : AppColors.accent)
                Text("packing.progress \(checklist.checkedCount) \(checklist.items.count)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }
}

/// Пункт чеклиста с отметкой: тап — собрано / не собрано.
struct ChecklistItemRow: View {
    let item: ChecklistItem
    let onToggle: @MainActor () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? AppColors.success : AppColors.textTertiary)
                Text(verbatim: item.title)
                    .font(AppTypography.body)
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? AppColors.textSecondary : AppColors.textPrimary)
                Spacer(minLength: 0)
                if item.gearID != nil {
                    Image(systemName: "backpack")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .accessibilityLabel(Text("checklist.fromGear"))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(item.isChecked ? .isSelected : [])
    }
}

/// Заголовок группы пунктов: иконка и название категории.
struct GearCategoryHeader: View {
    let category: GearCategory
    var trailing: String?

    var body: some View {
        HStack {
            Label(LocalizedStringKey(category.titleKey), systemImage: category.systemImage)
            Spacer(minLength: 0)
            if let trailing {
                Text(verbatim: trailing)
            }
        }
    }
}

// MARK: - Все чеклисты

/// «Чеклисты»: сборы, свои чеклисты и шаблоны редакции.
struct ChecklistsView: View {
    @Environment(ListsStore.self) private var lists
    @State private var startsPacking = false
    @State private var createsList = false
    @State private var opened: UUID?

    var body: some View {
        List {
            Section {
                ForEach(lists.packingLists) { packing in
                    NavigationLink {
                        ChecklistDetailView(checklistID: packing.id)
                    } label: {
                        ChecklistSummaryRow(checklist: packing)
                    }
                }
                .onDelete { offsets in
                    for packing in offsets.map({ lists.packingLists[$0] }) {
                        lists.delete(packing)
                    }
                }
                Button {
                    startsPacking = true
                } label: {
                    Label("packing.start", systemImage: "bag.badge.plus")
                }
            } header: {
                Text("checklists.section.packing")
            } footer: {
                if lists.packingLists.isEmpty {
                    Text("checklists.packing.empty")
                }
            }

            Section {
                ForEach(lists.ownLists) { list in
                    NavigationLink {
                        ChecklistDetailView(checklistID: list.id)
                    } label: {
                        ChecklistSummaryRow(checklist: list)
                    }
                }
                .onDelete { offsets in
                    for list in offsets.map({ lists.ownLists[$0] }) {
                        lists.delete(list)
                    }
                }
                Button {
                    createsList = true
                } label: {
                    Label("checklists.new", systemImage: "plus")
                }
            } header: {
                Text("checklists.section.mine")
            } footer: {
                if lists.ownLists.isEmpty {
                    Text("checklists.mine.empty")
                }
            }

            Section {
                ForEach(lists.templates) { template in
                    NavigationLink {
                        TemplateDetailView(template: template)
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(verbatim: template.title.text(for: PackingFormat.language))
                                .font(AppTypography.bodyEmphasis)
                            Text("checklist.itemCount \(template.items.count)")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                if lists.templates.isEmpty {
                    Text("checklists.templates.unavailable")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
            } header: {
                Text("checklists.section.templates")
            }
        }
        .navigationTitle("checklists.title")
        .sheet(isPresented: $startsPacking) {
            StartPackingView { opened = $0.id }
                .environment(lists)
        }
        .sheet(isPresented: $createsList) {
            ChecklistEditView(checklist: nil) { opened = $0 }
                .environment(lists)
        }
        .navigationDestination(item: $opened) { id in
            ChecklistDetailView(checklistID: id)
        }
        .task { await lists.loadTemplates() }
    }
}

// MARK: - Шаблон

/// Шаблон редакции: пункты по категориям, «Собраться» и «В мои чеклисты».
struct TemplateDetailView: View {
    let template: ChecklistTemplate

    @Environment(ListsStore.self) private var lists
    @State private var startsPacking = false
    @State private var opened: UUID?

    private struct CategoryGroup: Identifiable {
        let category: GearCategory
        let items: [ChecklistTemplate.Item]
        var id: GearCategory { category }
    }

    private var groups: [CategoryGroup] {
        GearCategory.allCases.compactMap { category in
            let items = template.items.filter { $0.category == category }
            return items.isEmpty ? nil : CategoryGroup(category: category, items: items)
        }
    }

    var body: some View {
        List {
            if let note = template.note {
                Section {
                    RecommendationBox(
                        text: note.text(for: PackingFormat.language),
                        color: AppColors.accent,
                        icon: "info.circle"
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    startsPacking = true
                } label: {
                    Label("packing.startFromThis", systemImage: "bag.badge.plus")
                }
                Button {
                    opened = lists.copyToMyLists(template, language: PackingFormat.language).id
                } label: {
                    Label("checklists.copyToMine", systemImage: "doc.on.doc")
                }
            } footer: {
                Text("checklists.copyToMine.footer")
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { item in
                        Text(verbatim: item.title.text(for: PackingFormat.language))
                            .font(AppTypography.body)
                    }
                } header: {
                    GearCategoryHeader(category: group.category)
                }
            }
        }
        .navigationTitle(Text(verbatim: template.title.text(for: PackingFormat.language)))
        .sheet(isPresented: $startsPacking) {
            StartPackingView(source: .template(template.id)) { opened = $0.id }
                .environment(lists)
        }
        .navigationDestination(item: $opened) { id in
            ChecklistDetailView(checklistID: id)
        }
    }
}

// MARK: - Чеклист и сборы

/// Чеклист с отметками: прогресс, пункты по категориям, добавление пунктов (в том числе из
/// экипировки), «Собраться», «Сбросить», удаление.
struct ChecklistDetailView: View {
    let checklistID: UUID

    @Environment(ListsStore.self) private var lists
    @Environment(\.dismiss) private var dismiss
    @State private var newItemTitle = ""
    @State private var newItemCategory: GearCategory = .other
    @State private var editing = false
    @State private var picksGear = false
    @State private var startsPacking = false
    @State private var confirmsDelete = false
    @State private var opened: UUID?

    var body: some View {
        if let checklist = lists.checklist(checklistID) {
            content(checklist)
        } else {
            EmptyStateView(
                icon: "checklist",
                title: String(localized: "checklist.notFound"),
                description: String(localized: "checklist.notFound.description")
            )
        }
    }

    private func content(_ checklist: Checklist) -> some View {
        List {
            Section {
                ChecklistProgressHeader(checklist: checklist)
            }

            ForEach(checklist.sections) { section in
                Section {
                    ForEach(section.items) { item in
                        ChecklistItemRow(item: item) {
                            lists.update(checklistID) { $0.toggle(itemID: item.id) }
                        }
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { section.items[$0].id })
                        lists.update(checklistID) { list in list.items.removeAll { ids.contains($0.id) } }
                    }
                } header: {
                    GearCategoryHeader(category: section.category)
                }
            }

            Section {
                HStack(spacing: AppSpacing.sm) {
                    TextField("checklist.newItem", text: $newItemTitle)
                        .submitLabel(.done)
                        .onSubmit(addItem)
                    Menu {
                        Picker("checklist.newItem.category", selection: $newItemCategory) {
                            ForEach(GearCategory.allCases) { category in
                                Label(LocalizedStringKey(category.titleKey), systemImage: category.systemImage)
                                    .tag(category)
                            }
                        }
                    } label: {
                        Image(systemName: newItemCategory.systemImage)
                            .accessibilityLabel(Text("checklist.newItem.category"))
                    }
                    Button(action: addItem) {
                        Image(systemName: "plus.circle.fill")
                            .accessibilityLabel(Text("checklist.addItem"))
                    }
                    .buttonStyle(.borderless)
                    .disabled(newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !lists.gear.isEmpty {
                    Button {
                        picksGear = true
                    } label: {
                        Label("checklist.addFromGear", systemImage: "backpack")
                    }
                }
            } header: {
                Text("checklist.add")
            } footer: {
                if checklist.items.count >= Checklist.itemLimit {
                    Text("checklist.limit")
                }
            }
        }
        .navigationTitle(Text(verbatim: checklist.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editing = true
                    } label: {
                        Label("checklist.edit", systemImage: "pencil")
                    }
                    if checklist.kind == .list {
                        Button {
                            startsPacking = true
                        } label: {
                            Label("packing.startFromThis", systemImage: "bag.badge.plus")
                        }
                    }
                    Button {
                        lists.update(checklistID) { $0.resetChecks() }
                    } label: {
                        Label("checklist.reset", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(checklist.checkedCount == 0)
                    Button(role: .destructive) {
                        confirmsDelete = true
                    } label: {
                        Label("checklist.delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel(Text("checklist.actions"))
                }
            }
        }
        .confirmationDialog("checklist.deleteConfirm", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("checklist.delete", role: .destructive) {
                lists.delete(checklist)
                dismiss()
            }
        }
        .sheet(isPresented: $editing) {
            ChecklistEditView(checklist: checklist)
                .environment(lists)
        }
        .sheet(isPresented: $picksGear) {
            GearPickerView(excluded: Set(checklist.items.compactMap(\.gearID))) { picked in
                lists.update(checklistID) { list in
                    for item in picked {
                        list.append(ChecklistItem(title: item.name, category: item.category, gearID: item.id))
                    }
                }
            }
            .environment(lists)
        }
        .sheet(isPresented: $startsPacking) {
            StartPackingView(source: .list(checklist.id)) { opened = $0.id }
                .environment(lists)
        }
        .navigationDestination(item: $opened) { id in
            ChecklistDetailView(checklistID: id)
        }
    }

    private func addItem() {
        let title = newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let category = newItemCategory
        lists.update(checklistID) { $0.append(ChecklistItem(title: title, category: category)) }
        newItemTitle = ""
    }
}

/// Прогресс сборов, день поездки и напоминание.
struct ChecklistProgressHeader: View {
    let checklist: Checklist

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if checklist.items.isEmpty {
                Text("checklist.empty.hint")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                HStack {
                    Text("packing.progress \(checklist.checkedCount) \(checklist.items.count)")
                        .font(AppTypography.bodyEmphasis)
                    Spacer(minLength: 0)
                    if checklist.isComplete {
                        Label("packing.complete", systemImage: "checkmark.seal.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.success)
                    }
                }
                ProgressView(value: checklist.progress)
                    .tint(checklist.isComplete ? AppColors.success : AppColors.accent)
            }
            if let day = checklist.tripDate {
                Label(PackingFormat.tripDay(day), systemImage: "calendar")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            if checklist.kind == .packing, checklist.tripDate != nil, let minutes = checklist.remindMinutes {
                Label("packing.reminder.at \(PackingFormat.time(minutes: minutes))", systemImage: "bell")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }
}

// MARK: - День поездки и напоминание

/// Поля «День поездки» и «Напомнить накануне» для сборов.
struct PackingDateFields: View {
    @Binding var hasDate: Bool
    @Binding var tripDay: Date
    @Binding var reminds: Bool
    @Binding var remindTime: Date
    let notificationsDenied: Bool

    var body: some View {
        Section {
            Toggle("packing.form.hasDate", isOn: $hasDate)
            if hasDate {
                DatePicker(
                    "packing.form.date",
                    selection: $tripDay,
                    in: Calendar.current.startOfDay(for: Date())...,
                    displayedComponents: .date
                )
                Toggle("packing.form.remind", isOn: $reminds)
                if reminds {
                    DatePicker("packing.form.remindTime", selection: $remindTime, displayedComponents: .hourAndMinute)
                }
            }
        } footer: {
            if hasDate && reminds {
                Text(notificationsDenied
                     ? LocalizedStringKey("packing.form.notificationsDenied")
                     : LocalizedStringKey("packing.form.remindFooter"))
            }
        }
    }
}

// MARK: - Собраться

/// По чему собираемся: шаблон редакции или свой чеклист.
enum PackingSource: Hashable {
    case template(String)
    case list(UUID)
}

/// «Собраться»: сборы по шаблону или своему чеклисту на день поездки, с напоминанием накануне.
struct StartPackingView: View {
    let onCreated: @MainActor (Checklist) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ListsStore.self) private var lists
    @State private var source: PackingSource?
    @State private var title = ""
    @State private var hasDate = true
    @State private var tripDay = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var reminds = true
    @State private var remindTime = PackingFormat.date(minutes: Checklist.defaultRemindMinutes)
    @State private var notificationsDenied = false

    init(source: PackingSource? = nil, onCreated: @escaping @MainActor (Checklist) -> Void) {
        self.onCreated = onCreated
        _source = State(initialValue: source)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("packing.form.source", selection: $source) {
                        Text("packing.form.chooseSource").tag(PackingSource?.none)
                        ForEach(lists.templates) { template in
                            Text(verbatim: template.title.text(for: PackingFormat.language))
                                .tag(Optional(PackingSource.template(template.id)))
                        }
                        ForEach(lists.ownLists) { list in
                            Text(verbatim: list.title)
                                .tag(Optional(PackingSource.list(list.id)))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    TextField("packing.form.title", text: $title)
                } footer: {
                    Text("packing.form.sourceFooter")
                }

                PackingDateFields(
                    hasDate: $hasDate,
                    tripDay: $tripDay,
                    reminds: $reminds,
                    remindTime: $remindTime,
                    notificationsDenied: notificationsDenied
                )
            }
            .navigationTitle("packing.start")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("packing.form.create", action: create)
                        .disabled(source == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: source) { previous, current in
                // Название по умолчанию — как у выбранного списка, если его не меняли вручную.
                if title.isEmpty || title == defaultTitle(previous) {
                    title = defaultTitle(current)
                }
            }
            .onChange(of: reminds) { _, isOn in
                guard isOn else { return }
                Task { notificationsDenied = !(await PackingReminders.requestPermission()) }
            }
            .task {
                await lists.loadTemplates()
                if title.isEmpty {
                    title = defaultTitle(source)
                }
            }
        }
    }

    private func defaultTitle(_ source: PackingSource?) -> String {
        switch source {
        case .template(let id): lists.templates.first { $0.id == id }?.title.text(for: PackingFormat.language) ?? ""
        case .list(let id): lists.checklist(id)?.title ?? ""
        case nil: ""
        }
    }

    private func create() {
        let day = hasDate ? CalendarDay(tripDay) : nil
        let minutes = hasDate && reminds ? PackingFormat.minutes(of: remindTime) : nil
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let created: Checklist
        switch source {
        case .template(let id):
            guard let template = lists.templates.first(where: { $0.id == id }) else { return }
            created = lists.startPacking(
                from: template, title: name, tripDate: day, remindMinutes: minutes, language: PackingFormat.language
            )
        case .list(let id):
            guard let list = lists.checklist(id) else { return }
            created = lists.startPacking(from: list, title: name, tripDate: day, remindMinutes: minutes)
        case nil:
            return
        }
        if minutes != nil {
            let lists = self.lists
            Task {
                if await PackingReminders.requestPermission() {
                    await PackingReminders.update(lists.checklists)
                }
            }
        }
        onCreated(created)
        dismiss()
    }
}

// MARK: - Название, день, напоминание

/// Новый чеклист или правка: название, у сборов — день поездки и напоминание.
struct ChecklistEditView: View {
    /// `nil` — новый свой чеклист.
    let checklist: Checklist?
    var onCreated: (@MainActor (UUID) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(ListsStore.self) private var lists
    @State private var title: String
    @State private var hasDate: Bool
    @State private var tripDay: Date
    @State private var reminds: Bool
    @State private var remindTime: Date
    @State private var notificationsDenied = false

    init(checklist: Checklist?, onCreated: (@MainActor (UUID) -> Void)? = nil) {
        self.checklist = checklist
        self.onCreated = onCreated
        _title = State(initialValue: checklist?.title ?? "")
        _hasDate = State(initialValue: checklist?.tripDate != nil)
        _tripDay = State(initialValue: checklist?.tripDate?.date()
            ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        _reminds = State(initialValue: checklist?.remindMinutes != nil || checklist?.tripDate == nil)
        _remindTime = State(initialValue: PackingFormat.date(minutes: checklist?.remindMinutes ?? Checklist.defaultRemindMinutes))
    }

    private var isPacking: Bool { checklist?.kind == .packing }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("checklist.form.title", text: $title)
                }
                if isPacking {
                    PackingDateFields(
                        hasDate: $hasDate,
                        tripDay: $tripDay,
                        reminds: $reminds,
                        remindTime: $remindTime,
                        notificationsDenied: notificationsDenied
                    )
                }
            }
            .navigationTitle(checklist == nil ? Text("checklists.new") : Text("checklist.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save", action: save)
                        .disabled(!(1...100).contains(title.trimmingCharacters(in: .whitespacesAndNewlines).count))
                }
            }
            .onChange(of: reminds) { _, isOn in
                guard isOn else { return }
                Task { notificationsDenied = !(await PackingReminders.requestPermission()) }
            }
        }
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let checklist else {
            let list = Checklist(title: name)
            lists.save(list)
            onCreated?(list.id)
            dismiss()
            return
        }
        let day = hasDate ? CalendarDay(tripDay) : nil
        let minutes = hasDate && reminds ? PackingFormat.minutes(of: remindTime) : nil
        let packing = isPacking
        lists.update(checklist.id) { list in
            list.title = name
            if packing {
                list.tripDate = day
                list.remindMinutes = minutes
            }
        }
        dismiss()
    }
}
