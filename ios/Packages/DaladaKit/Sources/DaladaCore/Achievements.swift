import Foundation

// MARK: - Достижения

/// Значок: прогресс и дата получения (RPC `my_achievements`). Видны только владельцу.
public struct Achievement: Codable, Equatable, Sendable, Identifiable {
    /// Код значка (`first_trip`, `distance_100`, …).
    public let id: String
    public let progress: Int
    public let target: Int
    /// Когда получен; `nil` — ещё нет.
    public let earnedAt: Date?
    /// Получен, а поздравление ещё не показано.
    public let isNew: Bool

    public init(id: String, progress: Int, target: Int, earnedAt: Date? = nil, isNew: Bool = false) {
        self.id = id
        self.progress = progress
        self.target = target
        self.earnedAt = earnedAt
        self.isNew = isNew
    }

    enum CodingKeys: String, CodingKey {
        case id = "achievement"
        case progress
        case target
        case earnedAt = "earned_at"
        case isNew = "is_new"
    }

    public var isEarned: Bool { earnedAt != nil }

    /// Доля пути к значку, 0…1; у полученного — 1.
    public var fraction: Double {
        if isEarned { return 1 }
        guard target > 0 else { return 0 }
        return min(max(Double(progress) / Double(target), 0), 1)
    }

    /// Известный приложению значок; новые значки с сервера, которых приложение ещё не знает, не
    /// показываются.
    public var kind: AchievementKind? { AchievementKind(rawValue: id) }
}

/// Значки, которые знает приложение (порядок — как на сервере).
public enum AchievementKind: String, CaseIterable, Sendable {
    case firstTrip = "first_trip"
    case distance100 = "distance_100"
    case nights5 = "nights_5"
    case firstCatch = "first_catch"
    case species5 = "species_5"
    case trophy3kg = "trophy_3kg"
    case places5 = "places_5"
    case firstPublicPlace = "first_public_place"
    case reviews5 = "reviews_5"
    case acceptedEdit = "accepted_edit"

    public var systemImage: String {
        switch self {
        case .firstTrip: "flag.fill"
        case .distance100: "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .nights5: "moon.stars.fill"
        case .firstCatch: "fish.fill"
        case .species5: "fish.circle.fill"
        case .trophy3kg: "trophy.fill"
        case .places5: "map.fill"
        case .firstPublicPlace: "mappin.and.ellipse"
        case .reviews5: "star.bubble.fill"
        case .acceptedEdit: "checkmark.seal.fill"
        }
    }

    /// В чём считается прогресс.
    public var unit: AchievementUnit {
        switch self {
        case .distance100: .kilometers
        case .trophy3kg: .grams
        default: .count
        }
    }
}

public enum AchievementUnit: Sendable {
    case count
    case kilometers
    case grams
}

extension [Achievement] {
    /// Значки, которые знает приложение, в порядке сервера.
    public var known: [Achievement] { filter { $0.kind != nil } }

    /// Полученные, сначала свежие.
    public var earnedRecentFirst: [Achievement] {
        known
            .filter(\.isEarned)
            .sorted { ($0.earnedAt ?? .distantPast) > ($1.earnedAt ?? .distantPast) }
    }

    /// Новые — для поздравления.
    public var fresh: [Achievement] { known.filter(\.isNew) }

    /// Ближайший к получению: больше всего пройдено, но ещё не получен.
    public var nextUp: Achievement? {
        known
            .filter { !$0.isEarned }
            .max { $0.fraction < $1.fraction }
    }
}
