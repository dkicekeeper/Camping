import Backend
import DaladaCore
import Foundation
import Observation
import Persistence

/// Статьи редакции: сохранённая копия (читаются без сети), потом свежие с сервера — не чаще раза
/// в час. «Сохранённые» — закладки на этом телефоне. Передаётся через `.environment`.
@MainActor
@Observable
final class ArticlesStore {
    /// Новые — выше.
    private(set) var articles: [Article] = []
    private(set) var savedIDs: Set<String>

    private let backend: BackendClient?
    private let cache: CacheStore?
    private let defaults: UserDefaults
    private var isLoading = false
    private var refreshedAt: Date?

    private static let savedKey = "articles.saved"

    init(backend: BackendClient?, cache: CacheStore? = nil, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.cache = cache
        self.defaults = defaults
        savedIDs = Set(defaults.stringArray(forKey: Self.savedKey) ?? [])
    }

    func loadIfNeeded() async {
        if articles.isEmpty, let cached = try? await cache?.load([Article].self, for: .articles), !cached.isEmpty {
            articles = cached.sorted(by: Article.newestFirst)
        }
        guard let backend, !isLoading else { return }
        if let refreshedAt, Date().timeIntervalSince(refreshedAt) < 3600 { return }
        isLoading = true
        defer { isLoading = false }
        if let loaded = try? await backend.articles(), !loaded.isEmpty {
            articles = loaded.sorted(by: Article.newestFirst)
            refreshedAt = Date()
            try? await cache?.save(loaded, for: .articles)
        }
    }

    func article(_ id: String) -> Article? {
        articles.first { $0.id == id }
    }

    var saved: [Article] {
        articles.filter { savedIDs.contains($0.id) }
    }

    /// Разделы, в которых есть статьи, — в порядке `ArticleCategory.allCases`.
    var categories: [ArticleCategory] {
        let present = Set(articles.map(\.category))
        return ArticleCategory.allCases.filter(present.contains)
    }

    func isSaved(_ article: Article) -> Bool {
        savedIDs.contains(article.id)
    }

    func toggleSaved(_ article: Article) {
        if savedIDs.contains(article.id) {
            savedIDs.remove(article.id)
        } else {
            savedIDs.insert(article.id)
        }
        defaults.set(savedIDs.sorted(), forKey: Self.savedKey)
    }
}
