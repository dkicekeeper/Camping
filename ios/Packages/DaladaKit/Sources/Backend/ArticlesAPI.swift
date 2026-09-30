import DaladaCore
import Foundation
import Supabase

// MARK: - Статьи

extension BackendClient {
    /// Опубликованные статьи редакции (для всех, в том числе гостей). Черновики сервер не отдаёт.
    public func articles() async throws -> [Article] {
        let rows: [Lenient<Article>] = try await supabase
            .from("articles")
            .select(
                "id,category,sort_order,published_on,title_ru,title_kk,title_en," +
                "summary_ru,summary_kk,summary_en,body_ru,body_kk,body_en"
            )
            .order("sort_order")
            .execute()
            .value
        return rows.compactMap(\.value)
    }
}
