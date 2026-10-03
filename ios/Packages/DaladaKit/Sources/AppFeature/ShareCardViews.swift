import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI
import UIKit

// MARK: - Лист «Картинка для Stories»

/// Лист с картинкой для Stories и Telegram: формат (Stories или пост), предпросмотр и «Поделиться».
/// Данные грузятся при открытии, картинка рисуется на телефоне (`ImageRenderer`, 1080 px в ширину).
struct ShareCardSheet<Model, Card: View>: View {
    let load: @MainActor () async -> Model?
    let message: @MainActor (Model) -> String
    @ViewBuilder let card: @MainActor (Model, ShareCardFormat) -> Card

    @Environment(\.dismiss) private var dismiss
    @State private var model: Model?
    @State private var isLoaded = false
    @State private var format: ShareCardFormat = .story
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.lg) {
                Picker("share.format", selection: $format) {
                    ForEach(ShareCardFormat.allCases) { format in
                        Text(LocalizedStringKey(format.titleKey)).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let image, let model {
                    ShareLink(
                        item: Image(uiImage: image),
                        message: Text(verbatim: message(model)),
                        preview: SharePreview(Text(verbatim: "Dalada"), image: Image(uiImage: image))
                    ) {
                        Label("share.send", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryButton()
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
            .navigationTitle("share.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close", systemImage: "xmark") { dismiss() }
                }
            }
            .task {
                model = await load()
                isLoaded = true
                render()
            }
            .onChange(of: format) { _, _ in render() }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                .accessibilityLabel(Text("share.title"))
        } else if isLoaded {
            EmptyStateView(icon: "photo", title: String(localized: "share.failed"), style: .error)
        } else {
            ProgressView()
        }
    }

    private func render() {
        guard let model else { return }
        let renderer = ImageRenderer(
            content: card(model, format)
                .frame(width: format.width, height: format.height)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = ShareCardFormat.scale
        image = renderer.uiImage
    }
}

// MARK: - Рамка картинки

/// Цвета картинок: тёмный фон с бирюзовым акцентом — картинка одинаковая в светлой и тёмной теме.
enum ShareCardStyle {
    static let top = Color(red: 0.06, green: 0.20, blue: 0.22)
    static let bottom = Color(red: 0.02, green: 0.05, blue: 0.07)
    static let accent = Color(red: 0.33, green: 0.85, blue: 0.78)
}

/// Фон (фото во весь кадр или градиент) и подпись «Dalada» внизу.
struct ShareCardFrame<Content: View>: View {
    let format: ShareCardFormat
    var photo: UIImage?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            brand
                .padding(.top, 20)
        }
        .padding(28)
        .frame(width: format.width, height: format.height, alignment: .topLeading)
        .foregroundStyle(.white)
        .background { background }
        .clipped()
    }

    @ViewBuilder
    private var background: some View {
        if let photo {
            Color.black
                .overlay {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                }
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.35), .clear, .black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipped()
        } else {
            LinearGradient(colors: [ShareCardStyle.top, ShareCardStyle.bottom], startPoint: .top, endPoint: .bottom)
        }
    }

    private var brand: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: "Dalada")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
            Spacer(minLength: 8)
            Text(verbatim: ShareCardLink.siteLabel)
                .font(.system(size: 11, weight: .medium))
                .opacity(0.7)
                .lineLimit(1)
        }
    }
}

/// Цифра и подпись под ней («12,4 км» / «Дистанция»).
private struct ShareCardStat: View {
    let value: String
    let titleKey: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(titleKey)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Поездка

/// Картинка поездки: вид, название, дата, линия трека (без начала и конца), цифры.
struct TripShareCardView: View {
    let card: TripShareCard
    let format: ShareCardFormat

    var body: some View {
        ShareCardFrame(format: format) {
            VStack(alignment: .leading, spacing: 6) {
                Label(LocalizedStringKey(card.activity.titleKey), systemImage: card.activity.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ShareCardStyle.accent)
                Text(verbatim: card.title)
                    .font(.system(size: format == .story ? 32 : 28, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(card.startedAt, format: .dateTime.day().month(.wide).year())
                    .font(.system(size: 14))
                    .opacity(0.7)
            }

            track
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 12)

            HStack(alignment: .top, spacing: 12) {
                ShareCardStat(value: TripFormat.distance(Double(card.distanceM)), titleKey: "trip.stat.distance")
                ShareCardStat(value: TripFormat.duration(Double(card.movingSeconds)), titleKey: "trip.stat.time")
                if card.elevationGainM > 0 {
                    ShareCardStat(value: TripFormat.elevation(Double(card.elevationGainM)), titleKey: "trip.stat.elevation")
                }
            }
        }
    }

    @ViewBuilder
    private var track: some View {
        let lines = TrackPreview.normalized(card.segments)
        if lines.isEmpty {
            Image(systemName: card.activity.systemImage)
                .font(.system(size: 96))
                .foregroundStyle(ShareCardStyle.accent.opacity(0.5))
        } else {
            ZStack {
                TrackLineShape(lines: lines, inset: 10)
                    .stroke(ShareCardStyle.accent.opacity(0.3), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                TrackLineShape(lines: lines, inset: 10)
                    .stroke(ShareCardStyle.accent, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Улов

/// Картинка улова: фото во весь кадр (если есть), вид, вес и длина, «отпущена», место и дата.
struct CatchShareCardView: View {
    let card: CatchShareCard
    let speciesName: String
    let photo: UIImage?
    let format: ShareCardFormat

    var body: some View {
        ShareCardFrame(format: format, photo: photo) {
            Spacer(minLength: 0)
            if photo == nil {
                Image(systemName: "fish.fill")
                    .font(.system(size: 110))
                    .foregroundStyle(ShareCardStyle.accent.opacity(0.85))
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("share.catch.title")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ShareCardStyle.accent)
                Text(verbatim: card.count > 1 ? "\(speciesName) ×\(card.count)" : speciesName)
                    .font(.system(size: 36, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if let metrics {
                    Text(verbatim: metrics)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                if card.released {
                    Label("catch.released", systemImage: "arrow.uturn.backward.circle")
                        .font(.system(size: 15, weight: .medium))
                }
                Text(verbatim: details)
                    .font(.system(size: 14))
                    .opacity(0.75)
                    .lineLimit(2)
            }
        }
    }

    /// «2,4 кг · 56 см».
    private var metrics: String? {
        var parts: [String] = []
        if let grams = card.weightGrams {
            parts.append(Measurement(value: Double(grams) / 1000, unit: UnitMass.kilograms)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...2)))))
        }
        if let millimeters = card.lengthMillimeters {
            parts.append(Measurement(value: Double(millimeters) / 10, unit: UnitLength.centimeters)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1)))))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// «Капшагай · 2 октября 2026 г.» (место — только публичное).
    private var details: String {
        let date = card.at.formatted(.dateTime.day().month(.wide).year())
        return [card.placeName, date].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Место

/// Данные для картинки места: собираются из карточки места.
struct PlaceShareCard {
    let name: String
    let type: PlaceType
    let rating: Double?
    let reviewsCount: Int
    let photo: UIImage?
}

/// Картинка места: фото во весь кадр (если есть), тип, название, оценка.
struct PlaceShareCardView: View {
    let card: PlaceShareCard
    let format: ShareCardFormat

    var body: some View {
        ShareCardFrame(format: format, photo: card.photo) {
            Spacer(minLength: 0)
            if card.photo == nil {
                Image(systemName: card.type.systemImage)
                    .font(.system(size: 110))
                    .foregroundStyle(ShareCardStyle.accent.opacity(0.85))
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey(card.type.titleKey))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ShareCardStyle.accent)
                Text(verbatim: card.name)
                    .font(.system(size: 34, weight: .bold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                if let rating = card.rating, card.reviewsCount > 0 {
                    Label {
                        Text("share.place.rating \(rating.formatted(.number.precision(.fractionLength(1)))) \(card.reviewsCount)")
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                    .font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Кнопки

/// «Картинка для Stories» своей поездки (значок в панели страницы поездки).
struct TripShareCardButton: View {
    let tripID: UUID
    let environment: AppEnvironment

    @State private var showsSheet = false

    var body: some View {
        Button {
            showsSheet = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .accessibilityLabel(Text("share.title"))
        }
        .sheet(isPresented: $showsSheet) {
            ShareCardSheet(
                load: { try? await environment.backend?.tripShareCard(tripID) },
                message: { card in String(localized: "share.message.trip \(card.title) \(ShareCardLink.site.absoluteString)") }
            ) { card, format in
                TripShareCardView(card: card, format: format)
            }
        }
    }
}

/// «Картинка для Stories» своего улова (кнопка в строке улова).
struct CatchShareCardButton: View {
    let catchID: UUID

    @Environment(SessionStore.self) private var session
    @Environment(SpeciesStore.self) private var speciesStore
    @State private var showsSheet = false

    private struct Loaded {
        let card: CatchShareCard
        let speciesName: String
        let photo: UIImage?
    }

    var body: some View {
        Button {
            showsSheet = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.accent)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
                .accessibilityLabel(Text("share.title"))
        }
        .buttonStyle(.borderless)
        .sheet(isPresented: $showsSheet) {
            ShareCardSheet(
                load: { await load() },
                message: { loaded in String(localized: "share.message.catch \(loaded.speciesName) \(ShareCardLink.site.absoluteString)") }
            ) { loaded, format in
                CatchShareCardView(card: loaded.card, speciesName: loaded.speciesName, photo: loaded.photo, format: format)
            }
        }
    }

    private func load() async -> Loaded? {
        guard let backend = session.backend,
              let card = try? await backend.catchShareCard(catchID)
        else { return nil }
        await speciesStore.loadIfNeeded()
        var photo: UIImage?
        if let path = card.photoPath,
           let url = try? await backend.signedMediaURLs(paths: [path])[path] {
            photo = await PhotoCache.shared.image(path: path, url: url)
        }
        return Loaded(card: card, speciesName: speciesStore.name(for: card.speciesID), photo: photo)
    }
}
