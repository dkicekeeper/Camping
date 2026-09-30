import Foundation

// MARK: - Пуш-уведомления

/// Окружение APNs: сборки из Xcode — `sandbox`, TestFlight и App Store — `production`.
public enum PushEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}

public enum PushToken {
    /// Токен устройства строкой: шестнадцатеричные цифры в нижнем регистре.
    public static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

/// Ссылка на обсуждение (из пуша об ответе): `dalada://thread/<id>`.
public enum ThreadLink {
    static let host = "thread"

    public static func url(threadID: UUID) -> URL {
        URL(string: "\(InviteLink.scheme)://\(host)/\(threadID.uuidString.lowercased())")!
    }

    public static func threadID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == InviteLink.scheme, url.host?.lowercased() == host else { return nil }
        return url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
    }
}
