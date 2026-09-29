import Foundation

/// Фото, готовое к загрузке: JPEG до 1600 px и превью до 400 px, без метаданных (геометки в том
/// числе). Готовит его телефон — см. `PhotoCompressor` в AppFeature.
public struct PhotoDraft: Identifiable, Equatable, Sendable {
    /// Он же id строки `media` и имя файла в хранилище.
    public let id: UUID
    public let full: Data
    public let thumbnail: Data
    public let width: Int
    public let height: Int

    public init(id: UUID = UUID(), full: Data, thumbnail: Data, width: Int, height: Int) {
        self.id = id
        self.full = full
        self.thumbnail = thumbnail
        self.width = width
        self.height = height
    }
}

/// Пути файлов в бакете `media`: `<автор>/<id фото>.jpg` и `<автор>/<id фото>_thumb.jpg`.
/// UUID — в нижнем регистре: так их пишет база, и так их проверяют политики хранилища.
public enum MediaPath {
    public static let bucket = "media"

    public static func full(owner: UUID, media: UUID) -> String {
        "\(owner.uuidString.lowercased())/\(media.uuidString.lowercased()).jpg"
    }

    public static func thumbnail(owner: UUID, media: UUID) -> String {
        "\(owner.uuidString.lowercased())/\(media.uuidString.lowercased())_thumb.jpg"
    }
}

/// Фото в отчёте места (`place_reports.media`).
public struct ReportMedia: Decodable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let catchID: UUID?
    public let path: String
    public let thumbnailPath: String
    public let width: Int?
    public let height: Int?

    public init(id: UUID, catchID: UUID?, path: String, thumbnailPath: String, width: Int?, height: Int?) {
        self.id = id
        self.catchID = catchID
        self.path = path
        self.thumbnailPath = thumbnailPath
        self.width = width
        self.height = height
    }

    enum CodingKeys: String, CodingKey {
        case id
        case catchID = "catch_id"
        case path
        case thumbnailPath = "thumb_path"
        case width
        case height
    }
}
