import DaladaCore
import DesignComponents
import DesignTokens
import MapEngine
import SwiftUI

/// «Карты без сети»: районы, которые можно скачать заранее, — карта открывается там без связи.
struct OfflineMapsView: View {
    let environment: AppEnvironment

    @State private var maps = OfflineMaps.shared

    var body: some View {
        List {
            Section {
                ForEach(MapRegions.all) { region in
                    OfflineRegionRow(
                        region: region,
                        state: maps.state(of: region),
                        download: { maps.download(region, styleURL: environment.config.mapStyleURL) },
                        pause: { maps.pause(region) },
                        remove: { maps.remove(region) }
                    )
                }
            } footer: {
                Text("offlineMaps.footer")
            }

            if maps.totalBytes > 0 {
                Section {
                    LabeledContent("offlineMaps.total") {
                        Text(verbatim: OfflineMapsFormat.size(maps.totalBytes))
                    }
                }
            }
        }
        .navigationTitle("offlineMaps.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Район: название, размер или ход скачивания, кнопка действия; смахнуть — удалить.
struct OfflineRegionRow: View {
    let region: MapRegion
    let state: OfflineMaps.State
    let download: () -> Void
    let pause: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(LocalizedStringKey(region.titleKey))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                details
            }
            Spacer(minLength: 0)
            action
        }
        .padding(.vertical, AppSpacing.xxs)
        .swipeActions {
            if hasData {
                Button("offlineMaps.delete", systemImage: "trash", role: .destructive, action: remove)
            }
        }
    }

    private var hasData: Bool {
        switch state {
        case .notDownloaded: false
        default: true
        }
    }

    @ViewBuilder
    private var details: some View {
        switch state {
        case .notDownloaded:
            Text("offlineMaps.estimate \(OfflineMapsFormat.size(region.estimatedBytes))")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        case .downloading(let progress, let bytes):
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                ProgressView(value: progress)
                Text("offlineMaps.progress \(Int(progress * 100)) \(OfflineMapsFormat.size(bytes))")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        case .paused(let progress, _):
            Text("offlineMaps.paused \(Int(progress * 100))")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        case .downloaded(let bytes):
            Label {
                Text("offlineMaps.downloaded \(OfflineMapsFormat.size(bytes))")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.accent)
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
        case .failed(let message):
            Text(verbatim: message.isEmpty ? String(localized: "offlineMaps.failed") : message)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.destructive)
        }
    }

    @ViewBuilder
    private var action: some View {
        switch state {
        case .notDownloaded, .failed, .paused:
            Button(action: download) {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("offlineMaps.download"))
        case .downloading:
            Button(action: pause) {
                Image(systemName: "pause.circle")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("offlineMaps.pause"))
        case .downloaded:
            EmptyView()
        }
    }
}

enum OfflineMapsFormat {
    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// «2 района · 80 МБ» для строки в «Лайфхаках».
    @MainActor
    static func summary(_ maps: OfflineMaps) -> String {
        let downloaded = MapRegions.all.filter {
            if case .downloaded = maps.state(of: $0) { true } else { false }
        }.count
        guard downloaded > 0 else { return String(localized: "offlineMaps.summary.none") }
        return String(localized: "offlineMaps.summary \(downloaded) \(size(maps.totalBytes))")
    }
}
