import Foundation

// MARK: - Статьи

/// Раздел статей.
public enum ArticleCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case tackle
    case knots
    case technique
    case cooking
    case safety
    case rulesEthics = "rules_ethics"
    case placesSeasons = "places_seasons"
    /// Незнакомый раздел из новой версии сервера.
    case other

    public var id: String { rawValue }

    /// Ключ названия в `Localizable.xcstrings`.
    public var titleKey: String { "article.category.\(rawValue)" }

    public var systemImage: String {
        switch self {
        case .tackle: "fish"
        case .knots: "link"
        case .technique: "figure.fishing"
        case .cooking: "flame"
        case .safety: "cross.case"
        case .rulesEthics: "leaf"
        case .placesSeasons: "calendar"
        case .other: "doc.text"
        }
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ArticleCategory(rawValue: raw) ?? .other
    }
}

/// Статья редакции — строка `articles`. Текст — подмножество Markdown (`ArticleMarkdown`).
public struct Article: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let category: ArticleCategory
    public let title: LocalizedText
    public let summary: LocalizedText
    public let body: LocalizedText
    public let publishedOn: CalendarDay?
    public let sortOrder: Int

    public init(
        id: String,
        category: ArticleCategory,
        title: LocalizedText,
        summary: LocalizedText,
        body: LocalizedText,
        publishedOn: CalendarDay? = nil,
        sortOrder: Int = 100
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.summary = summary
        self.body = body
        self.publishedOn = publishedOn
        self.sortOrder = sortOrder
    }

    /// Минут на чтение (≈180 слов в минуту), не меньше одной.
    public func readingMinutes(language: String) -> Int {
        let words = body.text(for: language).split { $0.isWhitespace }.count
        return max(1, Int((Double(words) / 180).rounded(.up)))
    }

    /// Новые — выше; в один день — по порядку редакции.
    public static func newestFirst(_ a: Article, _ b: Article) -> Bool {
        let aDay = a.publishedOn ?? CalendarDay(year: 1970, month: 1, day: 1)
        let bDay = b.publishedOn ?? CalendarDay(year: 1970, month: 1, day: 1)
        if aDay != bDay { return aDay > bDay }
        return (a.sortOrder, a.id) < (b.sortOrder, b.id)
    }

    enum CodingKeys: String, CodingKey {
        case id, category
        case titleRU = "title_ru", titleKK = "title_kk", titleEN = "title_en"
        case summaryRU = "summary_ru", summaryKK = "summary_kk", summaryEN = "summary_en"
        case bodyRU = "body_ru", bodyKK = "body_kk", bodyEN = "body_en"
        case publishedOn = "published_on"
        case sortOrder = "sort_order"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        category = (try? c.decode(ArticleCategory.self, forKey: .category)) ?? .other
        func text(_ ru: CodingKeys, _ kk: CodingKeys, _ en: CodingKeys) throws -> LocalizedText {
            LocalizedText(
                ru: try c.decode(String.self, forKey: ru),
                kk: try c.decodeIfPresent(String.self, forKey: kk) ?? "",
                en: try c.decodeIfPresent(String.self, forKey: en) ?? ""
            )
        }
        title = try text(.titleRU, .titleKK, .titleEN)
        summary = try text(.summaryRU, .summaryKK, .summaryEN)
        body = try text(.bodyRU, .bodyKK, .bodyEN)
        publishedOn = try? c.decodeIfPresent(CalendarDay.self, forKey: .publishedOn)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 100
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(category, forKey: .category)
        try c.encode(title.ru, forKey: .titleRU)
        try c.encode(title.kk, forKey: .titleKK)
        try c.encode(title.en, forKey: .titleEN)
        try c.encode(summary.ru, forKey: .summaryRU)
        try c.encode(summary.kk, forKey: .summaryKK)
        try c.encode(summary.en, forKey: .summaryEN)
        try c.encode(body.ru, forKey: .bodyRU)
        try c.encode(body.kk, forKey: .bodyKK)
        try c.encode(body.en, forKey: .bodyEN)
        try c.encodeIfPresent(publishedOn, forKey: .publishedOn)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

// MARK: - Разметка

/// Блок текста статьи. Строки внутри — с разметкой строки (`**жирный**`, `*курсив*`, ссылки).
public enum ArticleBlock: Hashable, Sendable {
    /// `## …` — уровень 2, `### …` — уровень 3.
    case heading(String, level: Int)
    case paragraph(String)
    /// `- пункт`
    case bullets([String])
    /// `1. шаг`
    case steps([String])
    /// `> выноска`
    case note(String)
}

/// Подмножество Markdown, которое показывает приложение (см. supabase/data/articles/README.md).
public enum ArticleMarkdown {
    public static func blocks(_ text: String) -> [ArticleBlock] {
        var blocks: [ArticleBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var steps: [String] = []
        var note: [String] = []

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            if !bullets.isEmpty { blocks.append(.bullets(bullets)) }
            if !steps.isEmpty { blocks.append(.steps(steps)) }
            if !note.isEmpty { blocks.append(.note(note.joined(separator: " "))) }
            paragraph = []
            bullets = []
            steps = []
            note = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if let heading = line.dropPrefix("### ") {
                flush()
                blocks.append(.heading(heading, level: 3))
            } else if let heading = line.dropPrefix("## ") {
                flush()
                blocks.append(.heading(heading, level: 2))
            } else if let item = line.dropPrefix("- ") {
                if bullets.isEmpty { flush() }
                bullets.append(item)
            } else if let item = stepText(line) {
                if steps.isEmpty { flush() }
                steps.append(item)
            } else if let quoted = line.dropPrefix(">") {
                if note.isEmpty { flush() }
                note.append(quoted.trimmingCharacters(in: .whitespaces))
            } else if !bullets.isEmpty || !steps.isEmpty || !note.isEmpty {
                // Продолжение пункта или выноски на следующей строке.
                if !note.isEmpty {
                    note.append(line)
                } else if !steps.isEmpty {
                    steps[steps.count - 1] += " " + line
                } else {
                    bullets[bullets.count - 1] += " " + line
                }
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    /// «12. Текст» → «Текст».
    private static func stepText(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: "."),
              line[..<dot].count <= 3,
              !line[..<dot].isEmpty,
              line[..<dot].allSatisfy(\.isNumber)
        else { return nil }
        let rest = line[line.index(after: dot)...]
        guard rest.first == " " else { return nil }
        return String(rest.dropFirst())
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
