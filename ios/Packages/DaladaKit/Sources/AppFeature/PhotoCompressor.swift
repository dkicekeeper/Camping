import DaladaCore
import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Готовит фото к загрузке: уменьшает до 1600 px (превью — до 400 px), поворачивает по EXIF и
/// перекодирует в JPEG. Метаданные исходника (геометка, модель телефона, время) в новый файл
/// не попадают — в него пишется только картинка.
enum PhotoCompressor {
    static let fullMaxPixels = 1600
    static let thumbnailMaxPixels = 400

    /// Фото из галереи. `nil` — не удалось прочитать или перекодировать.
    @MainActor
    static func draft(from item: PhotosPickerItem) async -> PhotoDraft? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        // Перекодирование — заметная работа для процессора, уводим её с главного потока.
        return await Task.detached(priority: .userInitiated) {
            PhotoCompressor.makeDraft(from: data)
        }.value
    }

    static func makeDraft(from data: Data) -> PhotoDraft? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let full = downsample(source, maxPixels: fullMaxPixels),
              let thumbnail = downsample(source, maxPixels: thumbnailMaxPixels),
              let fullData = jpeg(full, quality: 0.75),
              let thumbnailData = jpeg(thumbnail, quality: 0.7)
        else { return nil }
        return PhotoDraft(full: fullData, thumbnail: thumbnailData, width: full.width, height: full.height)
    }

    private static func downsample(_ source: CGImageSource, maxPixels: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
