import Foundation

// MARK: - Картинки для Stories и Telegram

/// Формат картинки: Stories (9:16) или пост (4:5). Размер — в точках, рисуется в 3 раза крупнее
/// (1080 × 1920 и 1080 × 1350 пикселей).
public enum ShareCardFormat: String, CaseIterable, Identifiable, Sendable {
    case story
    case post

    public var id: String { rawValue }
    public var titleKey: String { "share.format.\(rawValue)" }

    public var width: Double { 360 }

    public var height: Double {
        switch self {
        case .story: 640
        case .post: 450
        }
    }

    /// Масштаб отрисовки: 360 точек → 1080 пикселей.
    public static let scale: Double = 3
}

/// Данные для картинки своей поездки (`trip_share_card`): трек — как у гостя, без начала и конца.
public struct TripShareCard: Decodable, Sendable {
    public let activity: TripActivity
    public let title: String
    public let startedAt: Date
    public let endedAt: Date
    public let movingSeconds: Int
    public let distanceM: Int
    public let elevationGainM: Int
    public let segments: [[GeoPoint]]

    public init(
        activity: TripActivity,
        title: String,
        startedAt: Date,
        endedAt: Date,
        movingSeconds: Int,
        distanceM: Int,
        elevationGainM: Int,
        segments: [[GeoPoint]]
    ) {
        self.activity = activity
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.movingSeconds = movingSeconds
        self.distanceM = distanceM
        self.elevationGainM = elevationGainM
        self.segments = segments
    }

    enum CodingKeys: String, CodingKey {
        case activity
        case title
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case movingSeconds = "moving_seconds"
        case distanceM = "distance_m"
        case elevationGainM = "elevation_gain_m"
        case track
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activity = try c.decode(TripActivity.self, forKey: .activity)
        title = try c.decode(String.self, forKey: .title)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decode(Date.self, forKey: .endedAt)
        movingSeconds = try c.decodeIfPresent(Int.self, forKey: .movingSeconds) ?? 0
        distanceM = try c.decodeIfPresent(Int.self, forKey: .distanceM) ?? 0
        elevationGainM = try c.decodeIfPresent(Int.self, forKey: .elevationGainM) ?? 0
        // Трека может не быть (короткая поездка целиком в зоне приватности) — картинка без линии.
        segments = ((try? c.decodeIfPresent(TrackGeometry.self, forKey: .track)) ?? nil)?
            .segments.filter { $0.count >= 2 } ?? []
    }
}

/// Данные для картинки своего улова (`catch_share_card`): название места — только публичного.
public struct CatchShareCard: Decodable, Sendable {
    public let speciesID: String
    public let weightGrams: Int?
    public let lengthMillimeters: Int?
    public let count: Int
    public let released: Bool
    public let at: Date
    public let photoPath: String?
    public let placeName: String?

    public init(
        speciesID: String,
        weightGrams: Int?,
        lengthMillimeters: Int?,
        count: Int,
        released: Bool,
        at: Date,
        photoPath: String?,
        placeName: String?
    ) {
        self.speciesID = speciesID
        self.weightGrams = weightGrams
        self.lengthMillimeters = lengthMillimeters
        self.count = count
        self.released = released
        self.at = at
        self.photoPath = photoPath
        self.placeName = placeName
    }

    enum CodingKeys: String, CodingKey {
        case speciesID = "species_id"
        case weightGrams = "weight_g"
        case lengthMillimeters = "length_mm"
        case count
        case released
        case at
        case photoPath = "photo_path"
        case placeName = "place_name"
    }
}

/// Куда ведёт подпись на картинке и текст рядом с ней.
public enum ShareCardLink {
    public static var site: URL { LegalDocuments.baseURL }

    /// «dkicekeeper.github.io/Dalada» — для подписи на картинке, без схемы и косой черты в конце.
    public static var siteLabel: String {
        var text = site.absoluteString
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
