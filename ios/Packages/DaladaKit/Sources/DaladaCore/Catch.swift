import Foundation

/// Вид рыбы из справочника (`public.fish_species`).
public struct FishSpecies: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let nameRu: String
    public let nameKk: String
    public let nameEn: String
    public let nameLatin: String?
    public let sortOrder: Int

    public init(id: String, nameRu: String, nameKk: String, nameEn: String, nameLatin: String?, sortOrder: Int) {
        self.id = id
        self.nameRu = nameRu
        self.nameKk = nameKk
        self.nameEn = nameEn
        self.nameLatin = nameLatin
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case id
        case nameRu = "name_ru"
        case nameKk = "name_kk"
        case nameEn = "name_en"
        case nameLatin = "name_latin"
        case sortOrder = "sort_order"
    }

    /// Название на языке интерфейса (`ru`, `kk`, `en`; остальное — русский).
    public func name(for languageCode: String?) -> String {
        switch languageCode {
        case "kk": nameKk
        case "en": nameEn
        default: nameRu
        }
    }
}

/// Способ ловли (`public.fishing_method`).
public enum FishingMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    case spinning
    case feeder
    case float
    case fly
    case bottom
    case ice
    case other

    public var id: String { rawValue }
    public var titleKey: String { "catch.method.\(rawValue)" }
}

/// Условия на месте в чекине (`checkins.conditions`). Все поля необязательны.
public struct CheckinConditions: Codable, Equatable, Sendable {
    public enum Bite: String, Codable, CaseIterable, Sendable, Identifiable {
        case none, weak, moderate, good, excellent
        public var id: String { rawValue }
        public var titleKey: String { "conditions.bite.\(rawValue)" }
    }

    public enum Crowd: String, Codable, CaseIterable, Sendable, Identifiable {
        case empty, few, many
        public var id: String { rawValue }
        public var titleKey: String { "conditions.crowd.\(rawValue)" }
    }

    public enum Water: String, Codable, CaseIterable, Sendable, Identifiable {
        case clear, muddy
        public var id: String { rawValue }
        public var titleKey: String { "conditions.water.\(rawValue)" }
    }

    public enum Road: String, Codable, CaseIterable, Sendable, Identifiable {
        case fine, bad, impassable
        public var id: String { rawValue }
        public var titleKey: String { "conditions.road.\(rawValue)" }
    }

    public var bite: Bite?
    public var crowd: Crowd?
    public var water: Water?
    public var road: Road?

    public init(bite: Bite? = nil, crowd: Crowd? = nil, water: Water? = nil, road: Road? = nil) {
        self.bite = bite
        self.crowd = crowd
        self.water = water
        self.road = road
    }

    public var isEmpty: Bool { bite == nil && crowd == nil && water == nil && road == nil }

    /// Неизвестные значения (новые варианты с сервера) не ломают разбор — поле просто пустое.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bite = try? c.decodeIfPresent(Bite.self, forKey: .bite)
        crowd = try? c.decodeIfPresent(Crowd.self, forKey: .crowd)
        water = try? c.decodeIfPresent(Water.self, forKey: .water)
        road = try? c.decodeIfPresent(Road.self, forKey: .road)
    }

    enum CodingKeys: String, CodingKey {
        case bite, crowd, water, road
    }
}

/// Черновик улова в форме чекина.
public struct CatchDraft: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var speciesID: String
    /// Вес, кг (в базе — граммы).
    public var weightKg: Double?
    /// Длина, см (в базе — миллиметры).
    public var lengthCm: Double?
    public var count: Int
    public var method: FishingMethod?
    public var bait: String
    public var released: Bool
    public var hideSize: Bool
    /// Фото улова (одно).
    public var photo: PhotoDraft?

    public init(
        id: UUID = UUID(),
        speciesID: String,
        weightKg: Double? = nil,
        lengthCm: Double? = nil,
        count: Int = 1,
        method: FishingMethod? = nil,
        bait: String = "",
        released: Bool = false,
        hideSize: Bool = false,
        photo: PhotoDraft? = nil
    ) {
        self.id = id
        self.speciesID = speciesID
        self.weightKg = weightKg
        self.lengthCm = lengthCm
        self.count = count
        self.method = method
        self.bait = bait
        self.released = released
        self.hideSize = hideSize
        self.photo = photo
    }

    public var weightGrams: Int? { weightKg.map { Int(($0 * 1000).rounded()) } }
    public var lengthMillimeters: Int? { lengthCm.map { Int(($0 * 10).rounded()) } }

    public var isValid: Bool {
        let weightOK = weightGrams.map { (1...200_000).contains($0) } ?? true
        let lengthOK = lengthMillimeters.map { (1...3000).contains($0) } ?? true
        return weightOK && lengthOK && (1...1000).contains(count) && bait.count <= 100
    }
}

/// Черновик чекина: место, условия, заметка, уловы.
public struct CheckinDraft: Equatable, Sendable {
    public static let noteLimit = 2000
    /// Фото к самому чекину; к каждому улову — ещё по одному.
    public static let photoLimit = 5

    public var id: UUID
    public var placeID: UUID
    /// Когда человек был на месте. Из офлайн-очереди чекин может уйти позже — время остаётся этим.
    public var at: Date
    public var conditions: CheckinConditions
    public var note: String
    public var visibility: Visibility
    public var catches: [CatchDraft]
    /// Фото к чекину (не к улову).
    public var photos: [PhotoDraft]
    /// Где был телефон в момент чекина — по ней база подтверждает чекин (до 500 м от места).
    public var deviceLocation: GeoPoint?

    public init(
        id: UUID = UUID(),
        placeID: UUID,
        at: Date = Date(),
        conditions: CheckinConditions = CheckinConditions(),
        note: String = "",
        visibility: Visibility = .friends,
        catches: [CatchDraft] = [],
        photos: [PhotoDraft] = [],
        deviceLocation: GeoPoint? = nil
    ) {
        self.id = id
        self.placeID = placeID
        self.at = at
        self.conditions = conditions
        self.note = note
        self.visibility = visibility
        self.catches = catches
        self.photos = photos
        self.deviceLocation = deviceLocation
    }

    public var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isValid: Bool {
        trimmedNote.count <= Self.noteLimit
            && catches.allSatisfy(\.isValid)
            && photos.count <= Self.photoLimit
    }

    /// Все фото для загрузки: сначала к чекину, потом к уловам (с id улова).
    public var photoUploads: [PhotoUpload] {
        let checkinPhotos = photos.map { PhotoUpload(photo: $0, catchID: nil) }
        let catchPhotos = catches.compactMap { item in
            item.photo.map { PhotoUpload(photo: $0, catchID: item.id) }
        }
        return checkinPhotos + catchPhotos
    }
}

/// Фото к загрузке: к чекину (`catchID == nil`) или к улову.
public struct PhotoUpload: Equatable, Sendable {
    public let photo: PhotoDraft
    public let catchID: UUID?

    public init(photo: PhotoDraft, catchID: UUID?) {
        self.photo = photo
        self.catchID = catchID
    }
}

/// Улов в отчёте места. Вес и длина `nil`, если их нет или автор их скрыл.
public struct ReportCatch: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let speciesID: String
    public let count: Int
    public let released: Bool
    public let weightGrams: Int?
    public let lengthMillimeters: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case speciesID = "species_id"
        case count
        case released
        case weightGrams = "weight_g"
        case lengthMillimeters = "length_mm"
    }
}

/// Свежий отчёт места — строка `place_reports`.
public struct PlaceReport: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let authorID: UUID
    public let authorUsername: String?
    public let authorDisplayName: String?
    public let at: Date
    public let verified: Bool
    public let conditions: CheckinConditions
    public let note: String?
    public let isOwn: Bool
    public let catches: [ReportCatch]
    public let media: [ReportMedia]

    enum CodingKeys: String, CodingKey {
        case id = "checkin_id"
        case authorID = "author_id"
        case authorUsername = "author_username"
        case authorDisplayName = "author_display_name"
        case at
        case verified
        case conditions
        case note
        case isOwn = "is_own"
        case catches
        case media
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        authorID = try c.decode(UUID.self, forKey: .authorID)
        authorUsername = try c.decodeIfPresent(String.self, forKey: .authorUsername)
        authorDisplayName = try c.decodeIfPresent(String.self, forKey: .authorDisplayName)
        at = try c.decode(Date.self, forKey: .at)
        verified = try c.decode(Bool.self, forKey: .verified)
        conditions = try c.decode(CheckinConditions.self, forKey: .conditions)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        isOwn = try c.decode(Bool.self, forKey: .isOwn)
        catches = try c.decode([ReportCatch].self, forKey: .catches)
        // До миграции с фото сервер поля не отдавал.
        media = try c.decodeIfPresent([ReportMedia].self, forKey: .media) ?? []
    }
}

/// Свой улов — строка `my_catches`.
public struct MyCatch: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let speciesID: String
    public let weightGrams: Int?
    public let lengthMillimeters: Int?
    public let count: Int
    public let released: Bool
    public let at: Date
    public let visibility: Visibility
    public let placeID: UUID?
    public let placeName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case speciesID = "species_id"
        case weightGrams = "weight_g"
        case lengthMillimeters = "length_mm"
        case count
        case released
        case at
        case visibility
        case placeID = "place_id"
        case placeName = "place_name"
    }
}

extension CheckinConditions: Hashable {}
