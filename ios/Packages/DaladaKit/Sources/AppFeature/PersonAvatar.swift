import Backend
import DesignComponents
import DesignTokens
import Observation
import SwiftUI
import UIKit

/// Фото профилей: подписывает ссылки пачкой (аватары в ленте и списках появляются разом) и держит их
/// почти час. Картинки — в общем `PhotoCache`. Гостю подпись не выдаётся — у него инициалы.
@MainActor
@Observable
final class AvatarStore {
    private let backend: BackendClient?
    @ObservationIgnored private var urls: [String: (url: URL, until: Date)] = [:]
    @ObservationIgnored private var pending: Set<String> = []
    @ObservationIgnored private var batch: Task<[String: URL], Never>?

    init(backend: BackendClient?) {
        self.backend = backend
    }

    /// Картинка фото профиля; `nil` — фото нет, нет доступа или сети.
    func image(for path: String?) async -> UIImage? {
        guard let path else { return nil }
        if let image = PhotoCache.shared.cached(path) { return image }
        guard let url = await url(for: path) else { return nil }
        return await PhotoCache.shared.image(path: path, url: url)
    }

    private func url(for path: String) async -> URL? {
        if let entry = urls[path], entry.until > Date() { return entry.url }
        pending.insert(path)
        let task: Task<[String: URL], Never>
        if let batch {
            task = batch
        } else {
            task = Task { [weak self] in
                // Собираем запросы от всех аватаров на экране.
                try? await Task.sleep(for: .milliseconds(60))
                return await self?.signPending() ?? [:]
            }
            batch = task
        }
        return await task.value[path] ?? urls[path]?.url
    }

    private func signPending() async -> [String: URL] {
        let paths = Array(pending)
        pending = []
        batch = nil
        guard let backend, !paths.isEmpty,
              let signed = try? await backend.signedMediaURLs(paths: paths, expiresIn: 3600)
        else { return [:] }
        let until = Date().addingTimeInterval(50 * 60)
        for (path, url) in signed {
            urls[path] = (url, until)
        }
        return signed
    }
}

/// Аватар человека: фото профиля, пока его нет — инициалы (`AvatarView` из DesignKit).
struct PersonAvatar: View {
    let name: String?
    let path: String?
    var size: CGFloat = AppIconSize.avatar

    @Environment(AvatarStore.self) private var avatars: AvatarStore?
    @State private var image: UIImage?

    var body: some View {
        AvatarView(name: name, image: image.map { Image(uiImage: $0) }, size: size)
            .task(id: path) {
                image = await avatars?.image(for: path)
            }
    }
}
