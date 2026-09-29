import DaladaCore
import DesignTokens
import SwiftUI
import UIKit

/// Сторона квадратного превью фото в рядах.
private let photoThumbnailSize: CGFloat = 88

// MARK: - Фото в формах

/// Превью выбранного, ещё не загруженного фото.
struct PhotoDraftThumbnail: View {
    let photo: PhotoDraft

    var body: some View {
        Group {
            if let image = UIImage(data: photo.thumbnail) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(width: photoThumbnailSize, height: photoThumbnailSize)
        .background(AppColors.bgMuted)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}

/// Ряд выбранных фото с кнопкой удаления на каждом.
struct PhotoDraftStrip: View {
    let photos: [PhotoDraft]
    let onRemove: @MainActor (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(photos) { photo in
                    PhotoDraftThumbnail(photo: photo)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                onRemove(photo.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(AppColors.staticWhite, Color.black.opacity(0.55))
                            }
                            .buttonStyle(.borderless)
                            .padding(AppSpacing.xxs)
                            .accessibilityLabel(Text("photo.remove"))
                        }
                }
            }
            .padding(.vertical, AppSpacing.xxs)
        }
    }
}

// MARK: - Загруженные фото

/// Кэш картинок в памяти по пути в хранилище. Подписанные ссылки меняются при каждой загрузке
/// отчётов, а путь — нет, поэтому одно и то же фото за сессию скачивается один раз.
@MainActor
final class PhotoCache {
    static let shared = PhotoCache()

    private let images = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func cached(_ path: String) -> UIImage? {
        images.object(forKey: path as NSString)
    }

    func image(path: String, url: URL) async -> UIImage? {
        if let image = cached(path) { return image }
        if let task = inFlight[path] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let result = try? await URLSession.shared.data(from: url),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: result.0)
            else { return nil }
            // Декодирование — не на главном потоке.
            return await image.byPreparingForDisplay() ?? image
        }
        inFlight[path] = task
        let image = await task.value
        inFlight[path] = nil
        if let image {
            images.setObject(image, forKey: path as NSString)
        }
        return image
    }
}

/// Фото из хранилища по подписанной ссылке. Пока грузится — превью `placeholderPath`
/// (если оно уже в кэше) или индикатор.
struct RemotePhoto: View {
    let path: String
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderPath: String?

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image = image ?? PhotoCache.shared.cached(path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let placeholderPath, let placeholder = PhotoCache.shared.cached(placeholderPath) {
                Image(uiImage: placeholder)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .overlay { ProgressView() }
            } else if failed || url == nil {
                Image(systemName: "photo")
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            guard image == nil, let url else { return }
            image = await PhotoCache.shared.image(path: path, url: url)
            failed = image == nil
        }
    }
}

/// Ряд фото отчёта; тап открывает просмотр на весь экран.
struct ReportPhotoStrip: View {
    let media: [ReportMedia]
    let urls: [String: URL]

    @State private var opened: ReportMedia?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(media) { item in
                    Button {
                        opened = item
                    } label: {
                        RemotePhoto(path: item.thumbnailPath, url: urls[item.thumbnailPath])
                            .frame(width: photoThumbnailSize, height: photoThumbnailSize)
                            .background(AppColors.bgMuted)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("photo.open"))
                }
            }
        }
        .fullScreenCover(item: $opened) { item in
            PhotoViewer(media: media, urls: urls, selection: item.id)
        }
    }
}

/// Просмотр фото отчёта на весь экран, листание свайпом.
struct PhotoViewer: View {
    let media: [ReportMedia]
    let urls: [String: URL]

    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID

    init(media: [ReportMedia], urls: [String: URL], selection: UUID) {
        self.media = media
        self.urls = urls
        _selection = State(initialValue: selection)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(media) { item in
                    RemotePhoto(
                        path: item.path,
                        url: urls[item.path],
                        contentMode: .fit,
                        placeholderPath: item.thumbnailPath
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: media.count > 1 ? .automatic : .never))
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
