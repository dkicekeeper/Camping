import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

// MARK: - Строка статьи

/// Статья в списке: раздел, название, кратко, время чтения.
struct ArticleRow: View {
    let article: Article

    @Environment(ArticlesStore.self) private var store

    private var language: String { PackingFormat.language }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: article.category.systemImage)
                .font(.title3)
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: article.title.text(for: language))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                Text(verbatim: article.summary.text(for: language))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
                HStack(spacing: AppSpacing.xs) {
                    Text(LocalizedStringKey(article.category.titleKey))
                    Text(verbatim: "·")
                    Text("article.minutes \(article.readingMinutes(language: language))")
                    if store.isSaved(article) {
                        Image(systemName: "bookmark.fill")
                            .accessibilityLabel(Text("article.saved"))
                    }
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }
}

// MARK: - Все статьи

/// Что показывать в списке статей.
enum ArticleFilter: Hashable {
    case all
    case saved
    case category(ArticleCategory)
}

/// «Статьи и советы»: все, сохранённые, по разделам.
struct ArticlesListView: View {
    @Environment(ArticlesStore.self) private var store
    @State private var filter: ArticleFilter = .all

    private var shown: [Article] {
        switch filter {
        case .all: store.articles
        case .saved: store.saved
        case .category(let category): store.articles.filter { $0.category == category }
        }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        chip(Text("articles.filter.all"), .all)
                        chip(Text("articles.filter.saved"), .saved)
                        ForEach(store.categories) { category in
                            chip(Text(LocalizedStringKey(category.titleKey)), .category(category))
                        }
                    }
                    .padding(.vertical, AppSpacing.xxs)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.md, bottom: 0, trailing: AppSpacing.md))

            Section {
                if shown.isEmpty {
                    Text(filter == .saved ? LocalizedStringKey("articles.saved.empty") : LocalizedStringKey("articles.empty"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                ForEach(shown) { article in
                    NavigationLink {
                        ArticleView(article: article)
                    } label: {
                        ArticleRow(article: article)
                    }
                }
            }
        }
        .navigationTitle("articles.title")
        .task { await store.loadIfNeeded() }
    }

    private func chip(_ title: Text, _ value: ArticleFilter) -> some View {
        Button {
            filter = value
        } label: {
            title
        }
        .buttonStyle(.plain)
        .filterChipStyle(isSelected: filter == value)
    }
}

// MARK: - Статья

/// Читалка статьи: раздел, время чтения, текст с заголовками, списками и выносками;
/// «Сохранить» и «Поделиться».
struct ArticleView: View {
    let article: Article

    @Environment(ArticlesStore.self) private var store

    private var language: String { PackingFormat.language }
    private var blocks: [ArticleBlock] { ArticleMarkdown.blocks(article.body.text(for: language)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Label(LocalizedStringKey(article.category.titleKey), systemImage: article.category.systemImage)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accent)
                Text(verbatim: article.title.text(for: language))
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.textPrimary)
                Text("article.minutes \(article.readingMinutes(language: language))")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)

                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    ArticleBlockView(block: block)
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel(Text("article.share"))
                }
                Button {
                    store.toggleSaved(article)
                } label: {
                    Image(systemName: store.isSaved(article) ? "bookmark.fill" : "bookmark")
                        .accessibilityLabel(store.isSaved(article) ? Text("article.unsave") : Text("article.save"))
                }
            }
        }
    }

    /// Название, кратко и подпись — для «Поделиться».
    private var shareText: String {
        article.title.text(for: language) + "\n\n" + article.summary.text(for: language)
            + "\n\n" + String(localized: "article.shareSignature")
    }
}

/// Один блок текста статьи.
struct ArticleBlockView: View {
    let block: ArticleBlock

    var body: some View {
        switch block {
        case .heading(let text, let level):
            inline(text)
                .font(level == 2 ? Font.title3.weight(.semibold) : Font.headline)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.top, AppSpacing.sm)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            inline(text)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                        Text(verbatim: "•")
                        inline(item)
                    }
                }
            }
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textPrimary)
        case .steps(let items):
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                        Text(verbatim: "\(index + 1).")
                            .monospacedDigit()
                            .foregroundStyle(AppColors.accent)
                        inline(item)
                    }
                }
            }
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textPrimary)
        case .note(let text):
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: "info.circle")
                    .foregroundStyle(AppColors.accent)
                inline(text)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: 0)
            }
            .cardContentPadding()
            .cardStyle()
        }
    }

    /// Разметка внутри строки: **жирный**, *курсив*, ссылки.
    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return Text(attributed)
        }
        return Text(verbatim: text)
    }
}
