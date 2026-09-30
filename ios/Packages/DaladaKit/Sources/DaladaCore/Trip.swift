import Foundation

/// Вид поездки.
public enum TripActivity: String, Codable, CaseIterable, Sendable, Identifiable {
    case fishing
    case camping
    case hiking
    case other

    public var id: String { rawValue }
    public var titleKey: String { "trip.activity.\(rawValue)" }

    public var systemImage: String {
        switch self {
        case .fishing: "figure.fishing"
        case .camping: "tent"
        case .hiking: "figure.hiking"
        case .other: "figure.walk"
        }
    }
}

/// Точка трека с GPS.
public struct TrackPoint: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// Высота над уровнем моря, м.
    public var altitude: Double?
    /// Радиус погрешности, м.
    public var horizontalAccuracy: Double
    /// Скорость по GPS, м/с.
    public var speed: Double?
    public var timestamp: Date
    /// Первая точка после паузы: от предыдущей точки дистанцию и время не считаем.
    public var startsSegment: Bool

    public init(
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double,
        speed: Double? = nil,
        timestamp: Date,
        startsSegment: Bool = false
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.timestamp = timestamp
        self.startsSegment = startsSegment
    }

    public var coordinate: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }
}

/// Какие точки GPS записывать: без грубых, без «прыжков» и без дрожания на месте.
public struct TrackFilter: Sendable {
    /// Точки с погрешностью больше — отбрасываем, м.
    public var maxAccuracy: Double = 50
    /// Быстрее — это выброс GPS, а не движение, м/с (≈ 250 км/ч).
    public var maxSpeed: Double = 70
    /// Ближе к предыдущей точке — дрожание на месте, м.
    public var minDistance: Double = 5
    /// Стоя на месте, всё равно пишем точку раз в столько секунд — чтобы было видно время.
    public var maxSilence: TimeInterval = 60

    public init() {}

    public func accepts(_ point: TrackPoint, after previous: TrackPoint?) -> Bool {
        guard point.horizontalAccuracy >= 0, point.horizontalAccuracy <= maxAccuracy else { return false }
        guard let previous else { return true }
        let seconds = point.timestamp.timeIntervalSince(previous.timestamp)
        guard seconds > 0 else { return false }
        if point.startsSegment { return true }
        let distance = previous.coordinate.distance(to: point.coordinate)
        guard distance / seconds <= maxSpeed else { return false }
        return distance >= minDistance || seconds >= maxSilence
    }
}

/// Итоги трека: дистанция, время в движении, набор высоты, максимальная скорость.
/// Считаются по точкам по мере записи; те же числа получаются заново из сохранённых точек.
public struct TrackStats: Equatable, Sendable {
    /// Медленнее — стоим (рыбалка на берегу), м/с.
    public static let movingSpeed = 0.4
    /// Разрыв между точками дольше — не считаем движением (телефон не писал), с.
    public static let maxMovingGap: TimeInterval = 300
    /// Порог набора высоты: меньшие колебания — шум GPS, м.
    public static let elevationThreshold = 4.0
    /// Скорость по GPS учитываем, только если точка точная, м.
    public static let speedAccuracy = 20.0

    public private(set) var distanceM: Double = 0
    public private(set) var movingSeconds: TimeInterval = 0
    public private(set) var elevationGainM: Double = 0
    public private(set) var maxSpeedMps: Double = 0
    public private(set) var pointCount = 0
    public private(set) var lastPoint: TrackPoint?
    private var elevationBase: Double?

    public init() {}

    public init(points: [TrackPoint]) {
        self.init()
        for point in points { add(point) }
    }

    public mutating func add(_ point: TrackPoint) {
        if let last = lastPoint, !point.startsSegment {
            let seconds = point.timestamp.timeIntervalSince(last.timestamp)
            let distance = last.coordinate.distance(to: point.coordinate)
            distanceM += distance
            if seconds > 0, seconds <= Self.maxMovingGap, distance / seconds >= Self.movingSpeed {
                movingSeconds += seconds
            }
        }
        if let speed = point.speed, speed >= 0, point.horizontalAccuracy <= Self.speedAccuracy {
            maxSpeedMps = max(maxSpeedMps, speed)
        }
        if let altitude = point.altitude {
            if point.startsSegment || elevationBase == nil {
                elevationBase = altitude
            } else if let base = elevationBase {
                if altitude - base >= Self.elevationThreshold {
                    elevationGainM += altitude - base
                    elevationBase = altitude
                } else if base - altitude >= Self.elevationThreshold {
                    elevationBase = altitude
                }
            }
        }
        pointCount += 1
        lastPoint = point
    }
}

/// Готовая поездка для отправки на сервер.
public struct TripDraft: Identifiable, Equatable, Sendable {
    public static let titleLimit = 100
    public static let noteLimit = 2000

    public var id: UUID
    public var activity: TripActivity
    public var title: String
    public var note: String
    public var visibility: Visibility
    public var startedAt: Date
    public var endedAt: Date
    public var points: [TrackPoint]

    public init(
        id: UUID = UUID(),
        activity: TripActivity = .fishing,
        title: String = "",
        note: String = "",
        visibility: Visibility = .private,
        startedAt: Date,
        endedAt: Date,
        points: [TrackPoint] = []
    ) {
        self.id = id
        self.activity = activity
        self.title = title
        self.note = note
        self.visibility = visibility
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.points = points
    }

    public var stats: TrackStats { TrackStats(points: points) }
    public var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isValid: Bool {
        (1...Self.titleLimit).contains(trimmedTitle.count)
            && trimmedNote.count <= Self.noteLimit
            && endedAt >= startedAt
    }
}

/// Трек в EWKT для PostGIS: `SRID=4326;LINESTRING ZM (долгота широта высота время, …)`.
public enum TrackEncoding {
    /// `nil`, если точек меньше двух — линии нет.
    public static func ewkt(_ points: [TrackPoint]) -> String? {
        guard points.count >= 2 else { return nil }
        let coordinates = points.map { point in
            String(
                format: "%.6f %.6f %.1f %d",
                point.longitude,
                point.latitude,
                point.altitude ?? 0,
                Int(point.timestamp.timeIntervalSince1970.rounded())
            )
        }
        return "SRID=4326;LINESTRING ZM (" + coordinates.joined(separator: ", ") + ")"
    }
}

/// Поездка в списке — строка `trips` без трека.
public struct TripSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let activity: TripActivity
    public let title: String
    public let note: String?
    public let startedAt: Date
    public let endedAt: Date
    public let movingSeconds: Int
    public let distanceM: Int
    public let elevationGainM: Int
    public let maxSpeedMps: Double?
    public let visibility: Visibility

    enum CodingKeys: String, CodingKey {
        case id
        case activity
        case title
        case note
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case movingSeconds = "moving_seconds"
        case distanceM = "distance_m"
        case elevationGainM = "elevation_gain_m"
        case maxSpeedMps = "max_speed_mps"
        case visibility
    }

    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}

/// Поездка с треком (GeoJSON `LineString` из PostgREST).
public struct TripDetails: Codable, Hashable, Sendable {
    public let summary: TripSummary
    public let track: [GeoPoint]

    public init(summary: TripSummary, track: [GeoPoint]) {
        self.summary = summary
        self.track = track
    }

    enum CodingKeys: String, CodingKey {
        case track
    }

    struct LineString: Codable {
        var type = "LineString"
        var coordinates: [[Double]]
    }

    public init(from decoder: any Decoder) throws {
        summary = try TripSummary(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let line = try c.decodeIfPresent(LineString.self, forKey: .track)
        track = (line?.coordinates ?? []).compactMap { position in
            guard position.count >= 2 else { return nil }
            return GeoPoint(latitude: position[1], longitude: position[0])
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try summary.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        let line = track.isEmpty ? nil : LineString(coordinates: track.map { [$0.longitude, $0.latitude] })
        try c.encode(line, forKey: .track)
    }
}

/// Свой чекин за время поездки — строка `my_trip_checkins`.
public struct TripCheckin: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let at: Date
    public let verified: Bool
    public let placeID: UUID
    public let placeName: String?
    public let conditions: CheckinConditions
    public let note: String?
    public let catches: [ReportCatch]

    enum CodingKeys: String, CodingKey {
        case id = "checkin_id"
        case at
        case verified
        case placeID = "place_id"
        case placeName = "place_name"
        case conditions
        case note
        case catches
    }
}
