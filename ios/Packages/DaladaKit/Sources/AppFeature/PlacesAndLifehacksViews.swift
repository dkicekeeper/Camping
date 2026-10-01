import Backend
import DaladaCore
import DaladaUI
import DesignTokens
import MapEngine
import Persistence
import SwiftUI

/// Строка места: иконка типа, название, видимость, статус модерации.
struct PlaceRow: View {
    let place: PlaceSummary

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: place.type.systemImage)
                .font(.system(size: AppIconSize.md))
                .foregroundStyle(AppColors.accent)
                .frame(width: AppIconSize.avatar, height: AppIconSize.avatar)
                .background(AppColors.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: place.name)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                HStack(spacing: AppSpacing.sm) {
                    Label(LocalizedStringKey(place.visibility.titleKey), systemImage: place.visibility.systemImage)
                    if place.status == .pending {
                        Label("place.status.pending", systemImage: "hourglass")
                            .foregroundStyle(AppColors.warning)
                    }
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Вкладка «Лайфхаки»: правила и запреты, справочник рыб. Чеклисты, экипировка и статьи —
/// в следующих частях M5.
struct LifehacksHomeView: View {
    let environment: AppEnvironment

    @Environment(RulesStore.self) private var rules
    @Environment(ListsStore.self) private var lists
    @Environment(ArticlesStore.self) private var articles
    @State private var startsPacking = false
    @State private var opened: UUID?
    @State private var offlineMaps = OfflineMaps.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Ближайшие сборы с прогрессом.
                    if let packing = lists.upcomingPacking {
                        NavigationLink {
                            ChecklistDetailView(checklistID: packing.id)
                        } label: {
                            ChecklistSummaryRow(checklist: packing)
                        }
                    }
                    Button {
                        startsPacking = true
                    } label: {
                        Label("packing.start", systemImage: "bag.badge.plus")
                    }
                    NavigationLink {
                        ChecklistsView()
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Label("checklists.title", systemImage: "checklist")
                                .font(AppTypography.bodyEmphasis)
                            Text("checklists.summary \(lists.packingLists.count) \(lists.ownLists.count)")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    NavigationLink {
                        GearListView()
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Label("gear.title", systemImage: "backpack")
                                .font(AppTypography.bodyEmphasis)
                            Text(verbatim: lists.gear.isEmpty ? String(localized: "gear.summary.none") : GearFormat.summary(lists.gear))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    NavigationLink {
                        OfflineMapsView(environment: environment)
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Label("offlineMaps.title", systemImage: "map")
                                .font(AppTypography.bodyEmphasis)
                            Text(verbatim: OfflineMapsFormat.summary(offlineMaps))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                } header: {
                    Text("lifehacks.section.prep")
                } footer: {
                    if lists.hasUnsyncedChanges {
                        Label("lists.unsynced", systemImage: "icloud.slash")
                    }
                }

                Section {
                    NavigationLink {
                        RulesListView(environment: environment)
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Label("rules.title", systemImage: "exclamationmark.shield")
                                .font(AppTypography.bodyEmphasis)
                            if let summary = rulesSummary {
                                Text(verbatim: summary)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                    NavigationLink {
                        FishGuideView()
                    } label: {
                        Label("fish.guide.title", systemImage: "fish")
                            .font(AppTypography.bodyEmphasis)
                    }
                } header: {
                    Text("lifehacks.section.knowledge")
                }

                Section {
                    // Три последние статьи и ссылка на все.
                    ForEach(articles.articles.prefix(3)) { article in
                        NavigationLink {
                            ArticleView(article: article)
                        } label: {
                            ArticleRow(article: article)
                        }
                    }
                    if articles.articles.isEmpty {
                        Text("articles.empty")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    } else {
                        NavigationLink {
                            ArticlesListView()
                        } label: {
                            Label("articles.all", systemImage: "books.vertical")
                        }
                    }
                } header: {
                    Text("articles.title")
                }
            }
            .navigationTitle("tab.lifehacks")
            .navigationDestination(item: $opened) { id in
                ChecklistDetailView(checklistID: id)
            }
            .sheet(isPresented: $startsPacking) {
                StartPackingView { opened = $0.id }
                    .environment(lists)
            }
            .task { await rules.loadIfNeeded() }
            .task { await lists.loadTemplates() }
            .task { await articles.loadIfNeeded() }
        }
    }

    /// «Сейчас действуют запреты: 2» или ближайший: «Капшагайское водохранилище — с 5 апреля».
    private var rulesSummary: String? {
        guard let pack = rules.pack else { return nil }
        let today = RulesStore.today
        let active = pack.zones.filter { pack.banState(ofZone: $0.id, on: today) == .active }
        if !active.isEmpty {
            return String(localized: "rules.summary.active \(active.count)")
        }
        let upcoming = pack.regulations
            .filter { $0.kind == .fishingBan }
            .compactMap { regulation -> (Regulation, CalendarDay)? in
                switch pack.status(of: regulation, on: today) {
                case .soon(let start, _, _), .later(let start, _): (regulation, start)
                case .active, .yearRound: nil
                }
            }
            .min { $0.1 < $1.1 }
        guard let next = upcoming,
              let zoneID = next.0.zoneIDs.first,
              let zone = pack.zone(zoneID)
        else { return nil }
        return String(localized: "rules.summary.next \(zone.name.text(for: RulesStore.language)) \(RuleFormat.day(next.1))")
    }
}
