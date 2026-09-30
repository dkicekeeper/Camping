import Foundation
import Testing
@testable import DaladaCore

@Suite("Статьи")
struct ArticlesTests {
    @Test func parsesSupportedMarkdown() {
        let text = """
        Первый абзац,
        продолжение.

        ## Раздел
        - **Жирный** пункт
        - Второй пункт
        1. Шаг один
        2. Шаг два
           с продолжением

        ### Подраздел
        > Выноска
        > в две строки
        Абзац после.
        """
        #expect(ArticleMarkdown.blocks(text) == [
            .paragraph("Первый абзац, продолжение."),
            .heading("Раздел", level: 2),
            .bullets(["**Жирный** пункт", "Второй пункт"]),
            .steps(["Шаг один", "Шаг два с продолжением"]),
            .heading("Подраздел", level: 3),
            .note("Выноска в две строки Абзац после."),
        ])
        #expect(ArticleMarkdown.blocks("2026. Год в начале строки — не шаг.") == [.paragraph("2026. Год в начале строки — не шаг.")])
        #expect(ArticleMarkdown.blocks("").isEmpty)
    }

    @Test func readingTimeAndOrder() {
        let words = Array(repeating: "слово", count: 400).joined(separator: " ")
        let article = Article(
            id: "a", category: .safety,
            title: LocalizedText(ru: "Т", kk: "", en: "T"),
            summary: LocalizedText(ru: "С", kk: "", en: "S"),
            body: LocalizedText(ru: words, kk: "", en: "short"),
            publishedOn: CalendarDay(year: 2026, month: 9, day: 30), sortOrder: 20
        )
        #expect(article.readingMinutes(language: "ru") == 3)
        #expect(article.readingMinutes(language: "en") == 1)
        #expect(article.readingMinutes(language: "kk") == 3, "нет перевода — русский текст")

        let older = Article(id: "b", category: .knots, title: article.title, summary: article.summary,
                            body: article.body, publishedOn: CalendarDay(year: 2026, month: 9, day: 1), sortOrder: 1)
        let sameDay = Article(id: "c", category: .knots, title: article.title, summary: article.summary,
                              body: article.body, publishedOn: CalendarDay(year: 2026, month: 9, day: 30), sortOrder: 10)
        #expect([older, article, sameDay].sorted(by: Article.newestFirst).map(\.id) == ["c", "a", "b"])
    }

    @Test func decodesServerRowAndCaches() throws {
        let json = """
        [{"id": "ice_safety", "category": "safety", "sort_order": 10, "published_on": "2026-09-30",
          "title_ru": "Безопасность на льду", "title_kk": "Мұздағы қауіпсіздік", "title_en": "Ice safety",
          "summary_ru": "Кратко", "summary_kk": "", "summary_en": "Short",
          "body_ru": "## Раздел", "body_kk": "", "body_en": "## Section"},
         {"id": "future", "category": "fly_fishing", "title_ru": "Нахлыст", "summary_ru": "С", "body_ru": "Т"}]
        """
        let articles = try JSONDecoder().decode([Article].self, from: Data(json.utf8))
        #expect(articles[0].category == .safety)
        #expect(articles[0].summary.text(for: "kk") == "Кратко")
        #expect(articles[0].publishedOn == CalendarDay(year: 2026, month: 9, day: 30))
        #expect(articles[1].category == .other, "незнакомый раздел не ломает список")
        #expect(try JSONDecoder().decode([Article].self, from: JSONEncoder().encode(articles)) == articles)
    }
}
