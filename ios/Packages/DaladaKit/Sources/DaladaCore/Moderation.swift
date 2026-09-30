import Foundation

// MARK: - Жалобы

/// На что жалуются (как `report_target` в базе).
public enum ReportTarget: String, Codable, Sendable {
    case place
    case checkin
    case trip
    case review
    case thread
    case post
    case user
}

/// Причина жалобы (как `report_reason` в базе).
public enum ReportReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case spam
    case abuse
    case nsfw
    case poaching
    case privatePlace = "private_place"
    case falseInfo = "false_info"
    case other

    public var id: String { rawValue }

    /// Ключ названия в `Localizable.xcstrings`.
    public var titleKey: String { "moderation.reason.\(rawValue)" }

    /// Причины, подходящие для этого вида жалобы: «раскрыто чужое место» и «неправда» — не про людей.
    public static func options(for target: ReportTarget) -> [ReportReason] {
        switch target {
        case .user: [.spam, .abuse, .nsfw, .poaching, .other]
        case .place, .checkin, .trip, .review, .thread, .post: allCases
        }
    }
}
