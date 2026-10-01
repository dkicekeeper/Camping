import Foundation

/// Тип места (`public.place_type`).
public enum PlaceType: String, Codable, CaseIterable, Sendable, Identifiable {
    case fishingSpot = "fishing_spot"
    case waterBody = "water_body"
    case campsite
    case paidPond = "paid_pond"
    case base
    case parking
    case spring
    case tackleShop = "tackle_shop"
    case landmark

    public var id: String { rawValue }

    /// Ключ названия в `Localizable.xcstrings`.
    public var titleKey: String { "place.type.\(rawValue)" }

    public var systemImage: String {
        switch self {
        case .fishingSpot: "figure.fishing"
        case .waterBody: "water.waves"
        case .campsite: "tent"
        case .paidPond: "fish"
        case .base: "house"
        case .parking: "car"
        case .spring: "drop"
        case .tackleShop: "bag"
        case .landmark: "star"
        }
    }
}

/// Видимость (`public.visibility`).
public enum Visibility: String, Codable, CaseIterable, Sendable, Identifiable {
    case `public`
    case friends
    case `private`

    public var id: String { rawValue }
    public var titleKey: String { "visibility.\(rawValue)" }

    public var systemImage: String {
        switch self {
        case .public: "globe"
        case .friends: "person.2"
        case .private: "lock"
        }
    }
}

/// Статус модерации (`public.place_status`).
public enum PlaceStatus: String, Codable, Sendable {
    case pending
    case published
    case hidden
}

/// Место на карте или в списке — строка `places_in_bbox` / `my_places`.
public struct PlaceSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let ownerID: UUID
    public let type: PlaceType
    public let name: String
    /// Показанная точка: у чужих приблизительных мест — смещённый центр круга.
    public let coordinate: GeoPoint
    /// Показано приблизительно (кругом радиуса `radiusM`).
    public let isApproximate: Bool
    public let radiusM: Int
    public let visibility: Visibility
    public let status: PlaceStatus
    public let isOwn: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case type
        case name
        case lon
        case lat
        case isApproximate = "approximate"
        case radiusM = "radius_m"
        case visibility
        case status
        case isOwn = "is_own"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        ownerID = try c.decode(UUID.self, forKey: .ownerID)
        type = try c.decode(PlaceType.self, forKey: .type)
        name = try c.decode(String.self, forKey: .name)
        coordinate = GeoPoint(
            latitude: try c.decode(Double.self, forKey: .lat),
            longitude: try c.decode(Double.self, forKey: .lon)
        )
        isApproximate = try c.decode(Bool.self, forKey: .isApproximate)
        radiusM = try c.decode(Int.self, forKey: .radiusM)
        visibility = try c.decode(Visibility.self, forKey: .visibility)
        status = try c.decode(PlaceStatus.self, forKey: .status)
        // У гостя старый сервер отдавал null вместо false.
        isOwn = try c.decodeIfPresent(Bool.self, forKey: .isOwn) ?? false
    }

    /// В том же виде, что приходит с сервера, — для локального кэша.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ownerID, forKey: .ownerID)
        try c.encode(type, forKey: .type)
        try c.encode(name, forKey: .name)
        try c.encode(coordinate.longitude, forKey: .lon)
        try c.encode(coordinate.latitude, forKey: .lat)
        try c.encode(isApproximate, forKey: .isApproximate)
        try c.encode(radiusM, forKey: .radiusM)
        try c.encode(visibility, forKey: .visibility)
        try c.encode(status, forKey: .status)
        try c.encode(isOwn, forKey: .isOwn)
    }
}

/// Редакция Dalada — служебный аккаунт, автор редакционных мест (`private.editorial_id()`).
public enum Editorial {
    public static let username = "dalada"
}

/// Откуда место: добавлено человеком, редакцией или взято из OpenStreetMap (`attributes.source`).
public enum PlaceSource: String, Codable, Sendable {
    case editorial
    case osm
}

/// Карточка места — строка `place_card`.
public struct PlaceDetails: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let ownerID: UUID
    public let ownerUsername: String?
    public let type: PlaceType
    public let name: String
    public let description: String?
    public let coordinate: GeoPoint
    public let isApproximate: Bool
    public let radiusM: Int
    /// Точка подъезда; у огрублённых мест не отдаётся.
    public let accessPoint: GeoPoint?
    public let visibility: Visibility
    public let status: PlaceStatus
    public let isOwn: Bool
    /// Источник места редакции; у мест людей — `nil`.
    public let source: PlaceSource?
    /// «Информация»: рыба, подъезд, стоимость, удобства и прочее (`attributes`).
    public let info: PlaceAttributes

    /// Место редакции Dalada.
    public var isEditorial: Bool { ownerUsername == Editorial.username }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case ownerUsername = "owner_username"
        case type
        case name
        case description
        case lon
        case lat
        case isApproximate = "approximate"
        case radiusM = "radius_m"
        case accessLon = "access_lon"
        case accessLat = "access_lat"
        case attributes
        case visibility
        case status
        case isOwn = "is_own"
    }

    /// `attributes`: служебный источник и «Информация» — в одном объекте.
    struct Attributes: Codable, Hashable {
        var source: String?
        var info: PlaceAttributes

        enum SourceKey: String, CodingKey {
            case source
        }

        init(source: String?, info: PlaceAttributes) {
            self.source = source
            self.info = info
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: SourceKey.self)
            source = try? c.decodeIfPresent(String.self, forKey: .source)
            info = (try? PlaceAttributes(from: decoder)) ?? PlaceAttributes()
        }

        func encode(to encoder: any Encoder) throws {
            try info.encode(to: encoder)
            var c = encoder.container(keyedBy: SourceKey.self)
            try c.encodeIfPresent(source, forKey: .source)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        ownerID = try c.decode(UUID.self, forKey: .ownerID)
        ownerUsername = try c.decodeIfPresent(String.self, forKey: .ownerUsername)
        type = try c.decode(PlaceType.self, forKey: .type)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        coordinate = GeoPoint(
            latitude: try c.decode(Double.self, forKey: .lat),
            longitude: try c.decode(Double.self, forKey: .lon)
        )
        isApproximate = try c.decode(Bool.self, forKey: .isApproximate)
        radiusM = try c.decode(Int.self, forKey: .radiusM)
        if let lat = try c.decodeIfPresent(Double.self, forKey: .accessLat),
           let lon = try c.decodeIfPresent(Double.self, forKey: .accessLon) {
            accessPoint = GeoPoint(latitude: lat, longitude: lon)
        } else {
            accessPoint = nil
        }
        visibility = try c.decode(Visibility.self, forKey: .visibility)
        status = try c.decode(PlaceStatus.self, forKey: .status)
        // У гостя старый сервер отдавал null вместо false.
        isOwn = try c.decodeIfPresent(Bool.self, forKey: .isOwn) ?? false
        let attributes = try? c.decodeIfPresent(Attributes.self, forKey: .attributes)
        source = attributes?.source.flatMap(PlaceSource.init(rawValue:))
        info = attributes?.info ?? PlaceAttributes()
    }

    /// В том же виде, что приходит с сервера, — для локального кэша.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ownerID, forKey: .ownerID)
        try c.encode(ownerUsername, forKey: .ownerUsername)
        try c.encode(type, forKey: .type)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(coordinate.longitude, forKey: .lon)
        try c.encode(coordinate.latitude, forKey: .lat)
        try c.encode(isApproximate, forKey: .isApproximate)
        try c.encode(radiusM, forKey: .radiusM)
        try c.encode(accessPoint?.longitude, forKey: .accessLon)
        try c.encode(accessPoint?.latitude, forKey: .accessLat)
        try c.encode(Attributes(source: source?.rawValue, info: info), forKey: .attributes)
        try c.encode(visibility, forKey: .visibility)
        try c.encode(status, forKey: .status)
        try c.encode(isOwn, forKey: .isOwn)
    }
}

/// Черновик нового места из формы.
public struct PlaceDraft: Equatable, Sendable {
    public static let nameLimit = 80
    public static let descriptionLimit = 2000

    public var id: UUID
    public var type: PlaceType
    public var name: String
    public var description: String
    public var coordinate: GeoPoint
    public var visibility: Visibility
    /// Показывать другим кругом ~1 км вместо точной точки. Для «только я» не имеет смысла.
    public var isApproximate: Bool

    public init(
        id: UUID = UUID(),
        type: PlaceType = .fishingSpot,
        name: String = "",
        description: String = "",
        coordinate: GeoPoint,
        visibility: Visibility = .private,
        isApproximate: Bool = false
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.description = description
        self.coordinate = coordinate
        self.visibility = visibility
        self.isApproximate = isApproximate
    }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isValid: Bool {
        (1...Self.nameLimit).contains(trimmedName.count) && trimmedDescription.count <= Self.descriptionLimit
    }

    /// Флаг, который уйдёт в базу: для приватных мест огрубление не нужно.
    public var effectiveApproximate: Bool { visibility != .private && isApproximate }
}
