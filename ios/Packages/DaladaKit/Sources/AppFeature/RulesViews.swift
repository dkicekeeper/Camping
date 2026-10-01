import DaladaCore
import DaladaUI
import DesignComponents
import DesignTokens
import MapEngine
import SwiftUI

// MARK: - Форматы

/// Даты правил на языке интерфейса: «5 апреля», «5 апреля – 20 мая».
enum RuleFormat {
    static func day(_ day: CalendarDay) -> String {
        day.date(calendar: RulesStore.almatyCalendar).formatted(.dateTime.day().month(.wide))
    }

    static func period(_ start: CalendarDay, _ end: CalendarDay) -> String {
        day(start) + " – " + day(end)
    }

    /// Ежегодный срок без года (на примере високосного 2028-го).
    static func window(_ window: YearlyWindow) -> String {
        period(
            CalendarDay(year: 2028, month: window.startMonth, day: window.startDay),
            CalendarDay(year: 2028, month: window.endMonth, day: window.endDay)
        )
    }

    static func statusText(_ status: RuleStatus) -> String {
        switch status {
        case .yearRound:
            String(localized: "rules.status.yearRound")
        case .active(let end):
            String(localized: "rules.status.activeUntil \(day(end))")
        case .soon(let start, _, let days):
            days <= 0 ? String(localized: "rules.status.activeUntil \(day(start))")
                : String(localized: "rules.status.soon \(days) \(day(start))")
        case .later(let start, let end):
            period(start, end)
        }
    }

    static func statusColor(_ status: RuleStatus) -> Color {
        switch status {
        case .yearRound, .active: AppColors.destructive
        case .soon: AppColors.warning
        case .later: AppColors.textSecondary
        }
    }
}

/// Состояние срока: «Действует до 20 мая», «Через 16 дн. — с 5 апреля», «Круглый год».
struct RuleStatusBadge: View {
    let status: RuleStatus

    var body: some View {
        BadgeView(RuleFormat.statusText(status), color: RuleFormat.statusColor(status))
    }
}

/// «Информация справочная…» — под списками и карточками правил.
struct RulesDisclaimer: View {
    var body: some View {
        RecommendationBox(
            text: String(localized: "rules.disclaimer"),
            color: AppColors.accent,
            icon: "info.circle"
        )
    }
}

// MARK: - Правило

/// Правило: название, срок, кого касается, текст, промысловая мера, первоисточник.
struct RegulationCard: View {
    let regulation: Regulation
    let status: RuleStatus

    @Environment(SpeciesStore.self) private var speciesStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text(verbatim: regulation.title.text(for: RulesStore.language))
                    .font(AppTypography.bodyEmphasis)
                Spacer(minLength: 0)
                if regulation.kind == .fishingBan {
                    RuleStatusBadge(status: status)
                }
            }
            if regulation.kind == .fishingBan, let window = regulation.window {
                Text("rules.everyYear \(RuleFormat.window(window))")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            if regulation.gear == .amateur {
                Label("rules.gear.amateur", systemImage: "figure.fishing")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Text(verbatim: regulation.body.text(for: RulesStore.language))
                .font(AppTypography.bodySmall)
                .fixedSize(horizontal: false, vertical: true)

            if !regulation.minSizes.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    ForEach(sortedSizes, id: \.species) { item in
                        HStack {
                            Text(verbatim: speciesStore.name(for: item.species))
                            Spacer(minLength: 0)
                            Text("rules.minSize.cm \(item.cm)")
                                .monospacedDigit()
                        }
                        .font(AppTypography.bodySmall)
                    }
                }
                .padding(AppSpacing.sm)
                .background(AppColors.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.md))
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                if let url = regulation.sourceURL {
                    Link(destination: url) {
                        Label {
                            Text(verbatim: regulation.sourceTitle + ", " + regulation.sourceClause)
                                .multilineTextAlignment(.leading)
                        } icon: {
                            Image(systemName: "doc.text")
                        }
                    }
                }
                if let verified = regulation.verifiedOn {
                    Text("rules.verified \(verified.date(calendar: RulesStore.almatyCalendar).formatted(.dateTime.day().month(.wide).year()))")
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .font(AppTypography.caption)
        }
        .cardContentPadding()
        .cardStyle()
    }

    private var sortedSizes: [(species: String, cm: Int)] {
        regulation.minSizes
            .map { (species: $0.key, cm: $0.value) }
            .sorted { speciesStore.name(for: $0.species) < speciesStore.name(for: $1.species) }
    }
}

// MARK: - Список правил

/// Правила и запреты: действуют сейчас, скоро, остальные зоны и общие правила.
struct RulesListView: View {
    let environment: AppEnvironment

    @Environment(RulesStore.self) private var rules
    @Environment(SpeciesStore.self) private var speciesStore

    var body: some View {
        List {
            Section {
                RulesDisclaimer()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if let pack = rules.pack {
                let today = RulesStore.today
                let active = pack.zones.filter { pack.banState(ofZone: $0.id, on: today) == .active }
                let soon = pack.zones.filter { pack.banState(ofZone: $0.id, on: today) == .soon }
                let others = pack.zones.filter { pack.banState(ofZone: $0.id, on: today) == .none }
                if !active.isEmpty {
                    Section("rules.section.now") {
                        ForEach(active) { zone in zoneLink(zone, pack: pack, today: today) }
                    }
                }
                if !soon.isEmpty {
                    Section("rules.section.soon") {
                        ForEach(soon) { zone in zoneLink(zone, pack: pack, today: today) }
                    }
                }
                if !others.isEmpty {
                    Section("rules.section.zones") {
                        ForEach(others) { zone in zoneLink(zone, pack: pack, today: today) }
                    }
                }
                if !pack.generalRegulations.isEmpty {
                    Section("rules.section.general") {
                        ForEach(pack.generalRegulations) { regulation in
                            RegulationCard(regulation: regulation, status: pack.status(of: regulation, on: today))
                                .listRowInsets(EdgeInsets(top: AppSpacing.xs, leading: 0, bottom: AppSpacing.xs, trailing: 0))
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            } else {
                Section {
                    Text("rules.unavailable")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .navigationTitle("rules.title")
        .task { await rules.loadIfNeeded() }
        .task { await speciesStore.loadIfNeeded() }
        .refreshable { await rules.loadIfNeeded() }
    }

    private func zoneLink(_ zone: RuleZone, pack: RulesPack, today: CalendarDay) -> some View {
        NavigationLink {
            RuleZoneView(zoneID: zone.id, environment: environment)
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(verbatim: zone.name.text(for: RulesStore.language))
                    .font(AppTypography.bodyEmphasis)
                if let ban = mainBan(in: zone, pack: pack, today: today) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(verbatim: ban.title.text(for: RulesStore.language))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        RuleStatusBadge(status: pack.status(of: ban, on: today))
                    }
                }
            }
        }
    }

    /// Запрет зоны для строки списка: действующий, иначе ближайший.
    private func mainBan(in zone: RuleZone, pack: RulesPack, today: CalendarDay) -> Regulation? {
        let bans = pack.regulations(inZone: zone.id).filter { $0.kind == .fishingBan }
        return bans.first { pack.status(of: $0, on: today).isInForce } ?? bans.first
    }
}

// MARK: - Зона

/// Зона: граница на карте (приблизительная), пояснение, все правила зоны.
struct RuleZoneView: View {
    let zoneID: String
    let environment: AppEnvironment

    @Environment(RulesStore.self) private var rules
    @Environment(SpeciesStore.self) private var speciesStore

    var body: some View {
        Group {
            if let pack = rules.pack, let zone = pack.zone(zoneID) {
                content(zone, pack: pack)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(Text(verbatim: rules.pack?.zone(zoneID)?.name.text(for: RulesStore.language) ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .task { await rules.loadIfNeeded() }
        .task { await speciesStore.loadIfNeeded() }
    }

    private func content(_ zone: RuleZone, pack: RulesPack) -> some View {
        let today = RulesStore.today
        return ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if let camera = ZoneCamera(zone: zone) {
                    DaladaMapView(
                        styleURL: environment.config.mapStyleURL,
                        initialCenter: camera.center,
                        initialZoom: camera.zoom,
                        showsUserLocation: false,
                        ruleAreas: rules.mapAreas(on: today).filter { $0.id == zone.id }
                    )
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl))
                }
                Text(verbatim: zone.name.text(for: RulesStore.language))
                    .font(AppTypography.h3)
                if let note = zone.note {
                    Text(verbatim: note.text(for: RulesStore.language))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                let bans = pack.regulations(inZone: zone.id).filter { $0.kind == .fishingBan && $0.window != nil }
                if !bans.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        SectionHeaderView(String(localized: "rules.calendar"), systemImage: "calendar")
                        ZoneBanCalendar(bans: bans)
                    }
                }
                ForEach(pack.regulations(inZone: zone.id)) { regulation in
                    RegulationCard(regulation: regulation, status: pack.status(of: regulation, on: today))
                }
                RulesDisclaimer()
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
        }
    }
}

/// Календарь запретов зоны: в какие дни недели и месяца лов запрещён (`MonthCalendar` из
/// DesignKit; знак запрета — на каждом дне срока).
struct ZoneBanCalendar: View {
    let bans: [Regulation]

    @State private var range = CalendarRange()
    @State private var bansByDay: [Date: [Regulation]] = [:]

    var body: some View {
        MonthCalendar(
            range: range,
            itemsByDay: bansByDay,
            itemName: { $0.title.text(for: RulesStore.language) }
        ) { _ in
            Image(systemName: "nosign")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppColors.destructive)
        }
        .task(id: bans.map(\.id)) {
            let calendar = range.calendar
            bansByDay = range.itemsByDay(bans) { ban, interval in
                Self.days(of: ban, in: interval, calendar: calendar)
            }
        }
    }

    /// Дни из `interval`, в которые идёт срок запрета.
    nonisolated static func days(of ban: Regulation, in interval: DateInterval, calendar: Calendar) -> [Date] {
        guard let window = ban.window else { return [] }
        var days: [Date] = []
        var date = calendar.startOfDay(for: interval.start)
        while date < interval.end {
            let day = CalendarDay(date, calendar: calendar)
            if window.period(around: day).contains(day) {
                days.append(date)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return days
    }
}

/// Камера карты на зону: центр рамки и масштаб по её размеру.
struct ZoneCamera {
    let center: GeoPoint
    let zoom: Double

    init?(zone: RuleZone) {
        let points = zone.outline
        guard let minLat = points.map(\.latitude).min(), let maxLat = points.map(\.latitude).max(),
              let minLon = points.map(\.longitude).min(), let maxLon = points.map(\.longitude).max()
        else { return nil }
        center = GeoPoint(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = max(maxLat - minLat, (maxLon - minLon) * 0.75, 0.01)
        zoom = min(12, max(4, log2(360 / span) - 1.5))
    }
}

// MARK: - Правила в месте

/// «Правила здесь» в карточке места: действующие и близкие запреты, промысловая мера, ссылка на зону.
struct PlaceRulesSection: View {
    let coordinate: GeoPoint
    let environment: AppEnvironment

    @Environment(RulesStore.self) private var rules
    @Environment(SpeciesStore.self) private var speciesStore

    var body: some View {
        Group {
            if let pack = rules.pack, let zone = pack.zones(containing: coordinate).first {
                let today = RulesStore.today
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    SectionHeaderView(String(localized: "rules.here"), systemImage: "exclamationmark.shield")
                    ForEach(pack.activeBans(at: coordinate, on: today)) { ban in
                        RecommendationBox(
                            text: ban.title.text(for: RulesStore.language) + ": "
                                + RuleFormat.statusText(pack.status(of: ban, on: today)).lowercased(),
                            color: AppColors.destructive,
                            icon: "nosign"
                        )
                    }
                    ForEach(pack.upcomingBans(at: coordinate, on: today)) { ban in
                        RecommendationBox(
                            text: ban.title.text(for: RulesStore.language) + ": "
                                + RuleFormat.statusText(pack.status(of: ban, on: today)).lowercased(),
                            color: AppColors.warning,
                            icon: "calendar.badge.exclamationmark"
                        )
                    }
                    let sizes = pack.minSizes(at: coordinate)
                    if !sizes.isEmpty {
                        Text("rules.minSize.summary \(sizesText(sizes))")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    NavigationLink {
                        RuleZoneView(zoneID: zone.id, environment: environment)
                    } label: {
                        Label {
                            Text(verbatim: zone.name.text(for: RulesStore.language))
                        } icon: {
                            Image(systemName: "doc.text.magnifyingglass")
                        }
                        .font(AppTypography.bodySmall)
                    }
                }
            }
        }
        .task { await rules.loadIfNeeded() }
    }

    private func sizesText(_ sizes: [String: Int]) -> String {
        sizes
            .map { (name: speciesStore.name(for: $0.key), cm: $0.value) }
            .sorted { $0.name < $1.name }
            .map { "\($0.name) \($0.cm)" }
            .joined(separator: ", ")
    }
}

// MARK: - Справочник рыб

/// Справочник рыб: названия на трёх языках и латынь; промысловая мера по зонам.
struct FishGuideView: View {
    @Environment(SpeciesStore.self) private var speciesStore
    @Environment(RulesStore.self) private var rules

    var body: some View {
        List(speciesStore.species) { species in
            NavigationLink {
                FishDetailView(species: species)
            } label: {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(verbatim: species.name(for: SpeciesStore.languageCode))
                        .font(AppTypography.bodyEmphasis)
                    if let latin = species.nameLatin {
                        Text(verbatim: latin)
                            .font(AppTypography.caption)
                            .italic()
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .navigationTitle("fish.guide.title")
        .task { await speciesStore.loadIfNeeded() }
        .task { await rules.loadIfNeeded() }
    }
}

/// Вид рыбы: названия, промысловая мера в зонах, где она установлена.
struct FishDetailView: View {
    let species: FishSpecies

    @Environment(RulesStore.self) private var rules

    var body: some View {
        List {
            Section {
                LabeledContent("fish.name.ru") { Text(verbatim: species.nameRu) }
                LabeledContent("fish.name.kk") { Text(verbatim: species.nameKk) }
                LabeledContent("fish.name.en") { Text(verbatim: species.nameEn) }
                if let latin = species.nameLatin {
                    LabeledContent("fish.name.latin") { Text(verbatim: latin).italic() }
                }
            }
            Section {
                if sizes.isEmpty {
                    Text("fish.minSize.none")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                ForEach(sizes, id: \.zone) { item in
                    LabeledContent {
                        Text("rules.minSize.cm \(item.cm)")
                            .monospacedDigit()
                    } label: {
                        Text(verbatim: item.zone)
                    }
                }
            } header: {
                Text("fish.minSize.title")
            } footer: {
                Text("fish.minSize.footer")
            }
        }
        .navigationTitle(Text(verbatim: species.name(for: SpeciesStore.languageCode)))
        .task { await rules.loadIfNeeded() }
    }

    /// Зона → промысловая мера этого вида.
    private var sizes: [(zone: String, cm: Int)] {
        guard let pack = rules.pack else { return [] }
        return pack.regulations
            .compactMap { regulation -> [(zone: String, cm: Int)]? in
                guard let cm = regulation.minSizes[species.id] else { return nil }
                return regulation.zoneIDs.compactMap { id in
                    pack.zone(id).map { (zone: $0.name.text(for: RulesStore.language), cm: cm) }
                }
            }
            .flatMap { $0 }
    }
}
