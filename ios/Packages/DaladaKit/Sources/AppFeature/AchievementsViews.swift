import DaladaCore
import DesignComponents
import DesignSupport
import DesignTokens
import Persistence
import Sync
import SwiftUI

// MARK: - Раздел профиля

/// «Достижения» в профиле: последние полученные значки и ближайший к получению; «Все» — все значки.
/// Новые значки — поздравление, когда открыт «Профиль». Без сети — сохранённые (без поздравления).
struct AchievementsSection: View {
    let environment: AppEnvironment
    let userID: UUID

    @Environment(SyncEngine.self) private var sync
    @Environment(AppRouter.self) private var router
    @State private var achievements: [Achievement] = []
    @State private var isLoaded = false
    /// Новые значки из ответа сервера — ждут, когда откроют «Профиль».
    @State private var pendingFresh: [Achievement] = []
    @State private var celebration: AchievementCelebration?
    @State private var selected: Achievement?

    var body: some View {
        let known = achievements.known
        ProfileSection("achievements.title", systemImage: "rosette", showsAll: !known.isEmpty) {
            AchievementsView(achievements: known)
        } content: {
            if !known.isEmpty {
                summary(known)
            } else if isLoaded {
                ProfileSectionHint(text: String(localized: "achievements.empty"))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .task(id: userID) { await load() }
        .onChange(of: sync.sentCount) { _, _ in
            Task { await load() }
        }
        .onChange(of: router.selection) { _, _ in celebrateIfVisible() }
        .sheet(item: $celebration, onDismiss: { Task { await markSeen() } }) { item in
            NewAchievementsSheet(achievements: item.achievements)
        }
        .sheet(item: $selected) { achievement in
            AchievementDetailSheet(achievement: achievement)
        }
    }

    @ViewBuilder
    private func summary(_ known: [Achievement]) -> some View {
        let earned = known.earnedRecentFirst
        if !earned.isEmpty {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                ForEach(earned.prefix(4)) { achievement in
                    Button {
                        selected = achievement
                    } label: {
                        AchievementTile(achievement: achievement, medalSize: AppIconSize.xxxl)
                    }
                    .buttonStyle(.plain)
                }
                // Пустые ячейки держат ширину значков одинаковой.
                ForEach(0..<max(0, 4 - earned.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
        }
        if let next = known.nextUp {
            Button {
                selected = next
            } label: {
                AchievementProgressRow(achievement: next)
            }
            .buttonStyle(.plain)
        }
        Text("achievements.count \(earned.count) \(known.count)")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
    }

    private func load() async {
        defer { isLoaded = true }
        let key = CacheKey.achievements(userID)
        if let backend = environment.backend, let loaded = try? await backend.myAchievements() {
            achievements = loaded
            try? await environment.cache.save(loaded, for: key)
            pendingFresh = loaded.fresh
            celebrateIfVisible()
        } else if achievements.isEmpty, let saved = try? await environment.cache.load([Achievement].self, for: key) {
            achievements = saved
        }
    }

    /// Поздравление — только на открытом «Профиле» и только по свежему ответу сервера.
    private func celebrateIfVisible() {
        guard router.selection == .profile, celebration == nil, !pendingFresh.isEmpty else { return }
        celebration = AchievementCelebration(achievements: pendingFresh)
        pendingFresh = []
    }

    private func markSeen() async {
        try? await environment.backend?.markAchievementsSeen()
    }
}

/// Новые значки для листа поздравления.
private struct AchievementCelebration: Identifiable {
    let id = UUID()
    let achievements: [Achievement]
}

// MARK: - Все значки

/// Все значки сеткой: полученные — цветные, остальные — серые с прогрессом.
struct AchievementsView: View {
    let achievements: [Achievement]

    @State private var selected: Achievement?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: AppSpacing.md, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppSpacing.lg) {
                ForEach(achievements) { achievement in
                    Button {
                        selected = achievement
                    } label: {
                        AchievementTile(achievement: achievement, medalSize: AppIconSize.mega, showsProgress: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
        }
        .navigationTitle("achievements.title")
        .sheet(item: $selected) { achievement in
            AchievementDetailSheet(achievement: achievement)
        }
    }
}

// MARK: - Значок

/// Значок с названием; у неполученного — прогресс (если `showsProgress`).
private struct AchievementTile: View {
    let achievement: Achievement
    let medalSize: CGFloat
    var showsProgress = false

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            AchievementMedal(achievement: achievement, size: medalSize)
            if let kind = achievement.kind {
                Text(AchievementText.title(kind))
                    .font(AppTypography.caption)
                    .foregroundStyle(achievement.isEarned ? AppColors.textPrimary : AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if showsProgress && !achievement.isEarned {
                    Text(verbatim: AchievementText.progress(achievement, kind: kind))
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Круглый значок: полученный — цветной, иначе серый.
struct AchievementMedal: View {
    let achievement: Achievement
    let size: CGFloat

    var body: some View {
        IconView(
            source: .sfSymbol(achievement.kind?.systemImage ?? "rosette"),
            style: .circle(
                size: size,
                tint: .monochrome(achievement.isEarned ? AppColors.staticWhite : AppColors.textTertiary),
                backgroundColor: achievement.isEarned
                    ? CategoryColors.hexColor(for: achievement.id)
                    : AppColors.bgMuted,
                padding: size * 0.24
            )
        )
        .accessibilityHidden(true)
    }
}

/// Строка «ближе всего»: значок, название и полоска прогресса.
private struct AchievementProgressRow: View {
    let achievement: Achievement

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            AchievementMedal(achievement: achievement, size: AppIconSize.xl)
            if let kind = achievement.kind {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        Text("achievements.next")
                            .foregroundStyle(AppColors.textSecondary)
                        Text(AchievementText.title(kind))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer(minLength: 0)
                        Text(verbatim: AchievementText.progress(achievement, kind: kind))
                            .foregroundStyle(AppColors.textSecondary)
                            .monospacedDigit()
                    }
                    .font(AppTypography.bodySmall)
                    .lineLimit(1)
                    LinearProgressBar(value: achievement.fraction, height: 6)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Подробнее и поздравление

/// Значок крупно: что нужно сделать, прогресс или дата получения.
private struct AchievementDetailSheet: View {
    let achievement: Achievement

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            AchievementMedal(achievement: achievement, size: AppIconSize.budgetRing * 1.5)
            if let kind = achievement.kind {
                VStack(spacing: AppSpacing.sm) {
                    Text(AchievementText.title(kind))
                        .font(AppTypography.h3)
                    Text(AchievementText.detail(kind))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                if let earnedAt = achievement.earnedAt {
                    Text("achievements.earnedOn \(earnedAt.formatted(date: .long, time: .omitted))")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    VStack(spacing: AppSpacing.xs) {
                        LinearProgressBar(value: achievement.fraction)
                        Text(verbatim: AchievementText.progress(achievement, kind: kind))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
            Button("common.ok") { dismiss() }
                .primaryButton()
        }
        .padding(AppSpacing.xl)
        .presentationDetents([.medium])
    }
}

/// Поздравление с новыми значками.
private struct NewAchievementsSheet: View {
    let achievements: [Achievement]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Text(LocalizedStringKey(achievements.count == 1 ? "achievements.new.one" : "achievements.new.many"))
                .font(AppTypography.h2)
                .multilineTextAlignment(.center)
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    ForEach(achievements) { achievement in
                        if let kind = achievement.kind {
                            HStack(spacing: AppSpacing.md) {
                                AchievementMedal(achievement: achievement, size: AppIconSize.mega)
                                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                    Text(AchievementText.title(kind))
                                        .font(AppTypography.bodyEmphasis)
                                    Text(AchievementText.detail(kind))
                                        .font(AppTypography.bodySmall)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            Button("achievements.new.done") { dismiss() }
                .primaryButton()
        }
        .padding(AppSpacing.xl)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Тексты

/// Названия, условия и прогресс значков.
enum AchievementText {
    static func title(_ kind: AchievementKind) -> LocalizedStringResource {
        switch kind {
        case .firstTrip: "achievement.first_trip.title"
        case .distance100: "achievement.distance_100.title"
        case .nights5: "achievement.nights_5.title"
        case .firstCatch: "achievement.first_catch.title"
        case .species5: "achievement.species_5.title"
        case .trophy3kg: "achievement.trophy_3kg.title"
        case .places5: "achievement.places_5.title"
        case .firstPublicPlace: "achievement.first_public_place.title"
        case .reviews5: "achievement.reviews_5.title"
        case .acceptedEdit: "achievement.accepted_edit.title"
        }
    }

    static func detail(_ kind: AchievementKind) -> LocalizedStringResource {
        switch kind {
        case .firstTrip: "achievement.first_trip.detail"
        case .distance100: "achievement.distance_100.detail"
        case .nights5: "achievement.nights_5.detail"
        case .firstCatch: "achievement.first_catch.detail"
        case .species5: "achievement.species_5.detail"
        case .trophy3kg: "achievement.trophy_3kg.detail"
        case .places5: "achievement.places_5.detail"
        case .firstPublicPlace: "achievement.first_public_place.detail"
        case .reviews5: "achievement.reviews_5.detail"
        case .acceptedEdit: "achievement.accepted_edit.detail"
        }
    }

    /// «3 из 5», «86 из 100 км», «2,4 из 3 кг».
    static func progress(_ achievement: Achievement, kind: AchievementKind) -> String {
        let progress = min(achievement.progress, achievement.target)
        let target = achievement.target
        switch kind.unit {
        case .count:
            return String(localized: "achievements.progress.count \(progress) \(target)")
        case .kilometers:
            return String(localized: "achievements.progress.km \(progress) \(target)")
        case .grams:
            return String(localized: "achievements.progress.kg \(kilograms(progress)) \(kilograms(target))")
        }
    }

    private static func kilograms(_ grams: Int) -> String {
        (Double(grams) / 1000).formatted(.number.precision(.fractionLength(0...1)))
    }
}
