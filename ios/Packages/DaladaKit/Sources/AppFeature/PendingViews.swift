import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI
import Sync

/// Условия одной строкой: «Клёв: хороший · Людей: немного · Вода: мутная».
enum ConditionsText {
    static func make(_ conditions: CheckinConditions) -> String? {
        let pairs: [(String, String?)] = [
            ("conditions.bite", conditions.bite?.titleKey),
            ("conditions.crowd", conditions.crowd?.titleKey),
            ("conditions.water", conditions.water?.titleKey),
            ("conditions.road", conditions.road?.titleKey),
        ]
        let parts = pairs.compactMap { pair -> String? in
            let (category, value) = pair
            guard let value else { return nil }
            let categoryTitle = String(localized: String.LocalizationValue(category))
            let valueTitle = String(localized: String.LocalizationValue(value)).lowercased()
            return categoryTitle + ": " + valueTitle
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Свой чекин, ещё не принятый сервером: как отчёт, но с состоянием отправки.
/// В карточке места заголовок — «Вы», в профиле — название места.
struct PendingReportRow: View {
    let item: PendingCheckin
    var showsPlace = false

    @Environment(SpeciesStore.self) private var speciesStore
    @Environment(SyncEngine.self) private var sync
    @State private var confirmsDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                if showsPlace {
                    Text(verbatim: item.placeName)
                        .font(AppTypography.bodyEmphasis)
                } else {
                    Text("report.you")
                        .font(AppTypography.bodyEmphasis)
                }
                Spacer(minLength: 0)
                Text(item.at, style: .relative)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }

            status

            if let conditions = ConditionsText.make(item.conditions) {
                Text(verbatim: conditions)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            let note = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                Text(verbatim: note)
                    .font(AppTypography.bodySmall)
            }

            ForEach(item.catches) { catchDraft in
                CatchSummaryRow(
                    speciesName: speciesStore.name(for: catchDraft.speciesID),
                    count: catchDraft.count,
                    weightGrams: catchDraft.weightGrams,
                    lengthMillimeters: catchDraft.lengthMillimeters,
                    released: catchDraft.released
                )
            }

            if item.photoCount > 0 {
                Label {
                    Text(verbatim: "\(item.photoCount)")
                } icon: {
                    Image(systemName: "photo.on.rectangle")
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            }
        }
        .cardContentPadding()
        .cardStyle()
        .confirmationDialog("pending.discard.confirm", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("pending.discard", role: .destructive) {
                Task { await sync.discard(item.id) }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch item.state {
        case .waiting:
            Label("pending.waiting", systemImage: "icloud.and.arrow.up")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.warning)
        case .failed(let message):
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("pending.failed", systemImage: "exclamationmark.triangle.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.destructive)
                if !message.isEmpty {
                    Text(verbatim: message)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                HStack(spacing: AppSpacing.md) {
                    Button("common.retry") {
                        Task { await sync.retry(item.id) }
                    }
                    .secondaryButton()
                    Button("pending.discard", role: .destructive) {
                        confirmsDiscard = true
                    }
                    .secondaryButton()
                }
            }
        }
    }
}

/// «Ожидают отправки» в профиле: все поездки и чекины из очереди и «Отправить сейчас».
struct PendingQueueSection: View {
    @Environment(SyncEngine.self) private var sync

    private var hasWaiting: Bool {
        sync.pending.contains { $0.state == .waiting } || sync.pendingTrips.contains { $0.state == .waiting }
    }

    var body: some View {
        if !sync.pending.isEmpty || !sync.pendingTrips.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    SectionHeaderView(String(localized: "pending.title"), systemImage: "icloud.and.arrow.up")
                    Spacer(minLength: 0)
                    if sync.isSending {
                        ProgressView()
                    } else if hasWaiting {
                        Button("pending.sendNow") {
                            sync.kick(force: true)
                        }
                        .font(AppTypography.bodySmall)
                    }
                }
                ForEach(sync.pendingTrips) { item in
                    PendingTripRow(item: item)
                }
                ForEach(sync.pending) { item in
                    PendingReportRow(item: item, showsPlace: true)
                }
            }
        }
    }
}
