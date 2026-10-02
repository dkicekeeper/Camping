import Backend
import DaladaCore
import DaladaUI
import DesignComponents
import DesignTokens
import SwiftUI
import Sync

// MARK: - Звёзды

// MARK: - Отзывы

/// Отзывы публичного места в карточке: средняя оценка и распределение, свой отзыв, три самых
/// полезных и «Все отзывы».
struct PlaceReviewsSection: View {
    let place: PlaceDetails
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(ReactionStore.self) private var reactions
    @State private var summary: ReviewSummary?
    @State private var reviews: [PlaceReview] = []
    @State private var showsForm = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeaderView(String(localized: "reviews.title"), systemImage: "star.bubble")
            if let summary {
                if summary.reviewsCount > 0 {
                    ReviewSummaryView(summary: summary)
                } else {
                    Text("reviews.empty")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                reviewAction(summary)
            }
            ForEach(reviews) { review in
                ReviewRow(review: review) { blocked in
                    reviews.removeAll { $0.author.id == blocked }
                }
            }
            if let summary, summary.reviewsCount > reviews.count {
                NavigationLink {
                    ReviewsListView(placeID: place.id, placeName: place.name, environment: environment)
                } label: {
                    Text("reviews.all \(summary.reviewsCount)")
                        .font(AppTypography.bodySmall)
                }
            }
        }
        .task(id: place.id) { await load() }
        // Чекин из очереди дошёл до сервера — теперь можно оставить отзыв.
        .onChange(of: sync.sentCount) { _, _ in
            Task { await load() }
        }
        .sheet(isPresented: $showsForm, onDismiss: { Task { await load() } }) {
            ReviewFormView(placeID: place.id, placeName: place.name, existing: summary?.myReview, environment: environment)
        }
    }

    @ViewBuilder
    private func reviewAction(_ summary: ReviewSummary) -> some View {
        if session.profile != nil {
            if summary.myReview != nil {
                Button {
                    showsForm = true
                } label: {
                    Label("reviews.edit", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .secondaryButton()
            } else if summary.canReview {
                Button {
                    showsForm = true
                } label: {
                    Label("reviews.write", systemImage: "star")
                        .frame(maxWidth: .infinity)
                }
                .primaryButton()
            } else {
                Label("reviews.checkinFirst", systemImage: "mappin.circle")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func load() async {
        guard let backend = environment.backend else { return }
        summary = try? await backend.reviewSummary(place.id)
        reviews = (try? await backend.placeReviews(place.id, sort: .helpful, limit: 3)) ?? []
        for review in reviews {
            reactions.seed(ReactionKey(.review, review.id), review.helpful)
        }
        await reactions.loadCommentCounts(reviews.map { ReactionKey(.review, $0.id) })
    }
}

/// Средняя оценка, число отзывов и полоски по звёздам.
struct ReviewSummaryView: View {
    let summary: ReviewSummary

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.lg) {
            VStack(spacing: AppSpacing.xxs) {
                Text(verbatim: (summary.ratingAverage ?? 0).formatted(.number.precision(.fractionLength(1))))
                    .font(AppTypography.h2)
                    .monospacedDigit()
                RatingView(rating: summary.ratingAverage ?? 0, size: 12)
                Text("reviews.count \(summary.reviewsCount)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            VStack(spacing: AppSpacing.xxs) {
                ForEach((1...5).reversed(), id: \.self) { star in
                    HStack(spacing: AppSpacing.xs) {
                        Text(verbatim: "\(star)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 12)
                        LinearProgressBar(value: summary.share(of: star), color: AppColors.warning, height: 6)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("reviews.bar.accessibility \(star) \(summary.stars[star - 1])"))
                }
            }
        }
        .cardContentPadding()
        .cardStyle()
    }
}

/// Отзыв: автор, звёзды, когда был, текст, «Полезно».
struct ReviewRow: View {
    let review: PlaceReview
    /// Автора заблокировали — убрать его отзывы с экрана.
    var onBlocked: (@MainActor (UUID) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Text(verbatim: review.isOwn ? String(localized: "report.you") : review.author.label)
                    .font(AppTypography.bodyEmphasis)
                    .lineLimit(1)
                RatingView(rating: Double(review.rating), size: 12)
                Spacer(minLength: 0)
                Text(verbatim: review.createdAt.formatted(.relative(presentation: .named)))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
                if !review.isOwn {
                    ModerationMenu(target: .review, targetID: review.id, author: review.author) {
                        onBlocked?(review.author.id)
                    }
                }
            }
            if let visited = review.visitedOn {
                Text("reviews.visited \(visited.date().formatted(.dateTime.day().month(.wide).year()))")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            if let body = review.body, !body.isEmpty {
                ExpandableText(body, lineLimit: 4, font: AppTypography.bodySmall)
            }
            HStack(spacing: AppSpacing.md) {
                ReactionButton(key: ReactionKey(.review, review.id), isOwn: review.isOwn, style: .helpful)
                CommentsButton(key: ReactionKey(.review, review.id))
                if review.editedAt != nil {
                    Text("reviews.edited")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .cardContentPadding()
        .cardStyle()
    }
}

/// Все отзывы места с сортировкой: новые, полезные, высокие, низкие.
struct ReviewsListView: View {
    let placeID: UUID
    let placeName: String
    let environment: AppEnvironment

    private static let pageSize = 30

    @Environment(ReactionStore.self) private var reactions
    @State private var sort: ReviewSort = .new
    @State private var reviews: [PlaceReview] = []
    @State private var hasMore = true

    var body: some View {
        List {
            Section {
                Picker("reviews.sort", selection: $sort) {
                    ForEach(ReviewSort.allCases) { item in
                        Text(LocalizedStringKey(item.titleKey)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
            ForEach(reviews) { review in
                ReviewRow(review: review) { blocked in
                    reviews.removeAll { $0.author.id == blocked }
                }
                    .listRowSeparator(.hidden)
                    .onAppear {
                        if review.id == reviews.last?.id { Task { await loadMore() } }
                    }
            }
        }
        .listStyle(.plain)
        .navigationTitle(Text(verbatim: placeName))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sort) { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        guard let backend = environment.backend,
              let page = try? await backend.placeReviews(placeID, sort: sort, limit: Self.pageSize)
        else { return }
        reviews = page
        hasMore = page.count >= Self.pageSize
        seed(page)
    }

    private func loadMore() async {
        guard hasMore, let backend = environment.backend,
              let page = try? await backend.placeReviews(placeID, sort: sort, limit: Self.pageSize, offset: reviews.count)
        else { return }
        let known = Set(reviews.map(\.id))
        reviews += page.filter { !known.contains($0.id) }
        hasMore = page.count >= Self.pageSize
        seed(page)
    }

    private func seed(_ page: [PlaceReview]) {
        for review in page {
            reactions.seed(ReactionKey(.review, review.id), review.helpful)
        }
        Task { await reactions.loadCommentCounts(page.map { ReactionKey(.review, $0.id) }) }
    }
}

/// Отзыв: оценка, текст, когда были. Свой — можно изменить или удалить.
struct ReviewFormView: View {
    let placeID: UUID
    let placeName: String
    let existing: MyReview?
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var rating = 0
    @State private var text = ""
    @State private var visitedDate = Date()
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var confirmsDelete = false
    @State private var isPrepared = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RatingPicker(rating: $rating)
                        .padding(.vertical, AppSpacing.sm)
                } header: {
                    Text("reviews.form.rating")
                }

                Section {
                    TextField("reviews.form.placeholder", text: $text, axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text("reviews.form.text")
                } footer: {
                    if text.count > ReviewDraft.bodyLimit - 200 {
                        Text(verbatim: "\(text.count) / \(ReviewDraft.bodyLimit)")
                    }
                }

                Section {
                    DatePicker("reviews.form.visitedOn", selection: $visitedDate, in: ...Date(), displayedComponents: .date)
                }

                if let saveError {
                    Section {
                        Text(verbatim: saveError)
                            .foregroundStyle(AppColors.destructive)
                    }
                }

                if existing != nil {
                    Section {
                        Button("reviews.delete", role: .destructive) {
                            confirmsDelete = true
                        }
                    }
                }
            }
            .navigationTitle(Text(verbatim: placeName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("common.save") {
                            Task { await save() }
                        }
                        .disabled(!draft.isValid)
                    }
                }
            }
            .confirmationDialog("reviews.deleteConfirm", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("reviews.delete", role: .destructive) {
                    Task { await delete() }
                }
            }
            .onAppear {
                guard !isPrepared else { return }
                isPrepared = true
                let initial = ReviewDraft(placeID: placeID, existing: existing)
                rating = initial.rating
                text = initial.body
                visitedDate = initial.visitedOn.date()
            }
        }
    }

    private var draft: ReviewDraft {
        var draft = ReviewDraft(placeID: placeID, existing: existing)
        draft.rating = rating
        draft.body = text
        draft.visitedOn = CalendarDay(visitedDate)
        return draft
    }

    private func save() async {
        guard let backend = environment.backend, draft.isValid else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await backend.saveReview(draft)
            dismiss()
        } catch {
            saveError = CommunityMessage.text(for: error)
        }
    }

    private func delete() async {
        guard let backend = environment.backend, let existing else { return }
        do {
            try await backend.deleteReview(existing.id)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// Понятный текст ошибки для отзывов и обсуждений.
enum CommunityMessage {
    static func text(for error: any Error) -> String {
        if let refusal = CommunityRefusal(error) {
            return String(localized: String.LocalizationValue(refusal.messageKey))
        }
        return error.localizedDescription
    }
}

// MARK: - Обсуждения

/// Обсуждения публичного места в карточке: три свежих по активности, «Все», «Новое обсуждение».
struct PlaceThreadsSection: View {
    let place: PlaceDetails
    let environment: AppEnvironment

    @Environment(SessionStore.self) private var session
    @State private var threads: [ThreadSummary] = []
    @State private var isLoaded = false
    @State private var showsForm = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                SectionHeaderView(String(localized: "threads.title"), systemImage: "bubble.left.and.bubble.right")
                Spacer(minLength: 0)
                if threads.count > 3 {
                    NavigationLink {
                        ThreadsListView(placeID: place.id, placeName: place.name, environment: environment)
                    } label: {
                        Text("threads.all")
                            .font(AppTypography.bodySmall)
                    }
                }
            }
            if threads.isEmpty && isLoaded {
                Text("threads.empty")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
            ForEach(threads.prefix(3)) { thread in
                NavigationLink {
                    ThreadView(threadID: thread.id, environment: environment)
                } label: {
                    ThreadRow(thread: thread)
                }
                .buttonStyle(.plain)
            }
            if session.profile != nil {
                Button {
                    showsForm = true
                } label: {
                    Label("threads.new", systemImage: "plus.bubble")
                        .frame(maxWidth: .infinity)
                }
                .secondaryButton()
            }
        }
        .task(id: place.id) { await load() }
        .sheet(isPresented: $showsForm, onDismiss: { Task { await load() } }) {
            ThreadFormView(placeID: place.id, placeName: place.name, environment: environment)
        }
    }

    private func load() async {
        defer { isLoaded = true }
        guard let backend = environment.backend else { return }
        threads = (try? await backend.placeThreads(place.id, limit: 4)) ?? []
    }
}

/// Строка обсуждения: заголовок, начало текста, ответы и последняя активность.
struct ThreadRow: View {
    let thread: ThreadSummary

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(verbatim: thread.title)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
            if !thread.bodyPreview.isEmpty {
                Text(verbatim: thread.bodyPreview)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: AppSpacing.sm) {
                Label {
                    Text(verbatim: "\(thread.postsCount)")
                } icon: {
                    Image(systemName: "bubble.left")
                }
                Text(verbatim: thread.author.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(verbatim: thread.lastActivityAt.formatted(.relative(presentation: .named)))
                    .lineLimit(1)
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardContentPadding()
        .cardStyle()
        .contentShape(Rectangle())
    }
}

/// Все обсуждения места.
struct ThreadsListView: View {
    let placeID: UUID
    let placeName: String
    let environment: AppEnvironment

    private static let pageSize = 30

    @Environment(SessionStore.self) private var session
    @State private var threads: [ThreadSummary] = []
    @State private var hasMore = true
    @State private var showsForm = false

    var body: some View {
        List {
            ForEach(threads) { thread in
                NavigationLink {
                    ThreadView(threadID: thread.id, environment: environment)
                } label: {
                    ThreadRow(thread: thread)
                }
                .listRowSeparator(.hidden)
                .onAppear {
                    if thread.id == threads.last?.id { Task { await loadMore() } }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("threads.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.profile != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("threads.new", systemImage: "plus") {
                        showsForm = true
                    }
                }
            }
        }
        .sheet(isPresented: $showsForm, onDismiss: { Task { await reload() } }) {
            ThreadFormView(placeID: placeID, placeName: placeName, environment: environment)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        guard let backend = environment.backend,
              let page = try? await backend.placeThreads(placeID, limit: Self.pageSize)
        else { return }
        threads = page
        hasMore = page.count >= Self.pageSize
    }

    private func loadMore() async {
        guard hasMore, let backend = environment.backend,
              let page = try? await backend.placeThreads(placeID, limit: Self.pageSize, offset: threads.count)
        else { return }
        let known = Set(threads.map(\.id))
        threads += page.filter { !known.contains($0.id) }
        hasMore = page.count >= Self.pageSize
    }
}

/// Новое обсуждение: заголовок и текст.
struct ThreadFormView: View {
    let placeID: UUID
    let placeName: String
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var threadID = UUID()
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("threads.form.titlePlaceholder", text: $title)
                } header: {
                    Text("threads.form.title")
                } footer: {
                    Text("threads.form.hint")
                }
                Section("threads.form.text") {
                    TextField("threads.form.textPlaceholder", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                }
                if let saveError {
                    Section {
                        Text(verbatim: saveError)
                            .foregroundStyle(AppColors.destructive)
                    }
                }
            }
            .navigationTitle(Text(verbatim: placeName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("threads.form.publish") {
                            Task { await save() }
                        }
                        .disabled(!draft.isValid)
                    }
                }
            }
        }
    }

    private var draft: ThreadDraft {
        var draft = ThreadDraft(placeID: placeID, id: threadID)
        draft.title = title
        draft.body = text
        return draft
    }

    private func save() async {
        guard let backend = environment.backend, draft.isValid else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await backend.createThread(draft)
            // Ответы на обсуждение приходят пушем — объясним и спросим разрешение.
            Task { await NotificationPrimer.shared.offer() }
            dismiss()
        } catch {
            saveError = CommunityMessage.text(for: error)
        }
    }
}

/// Обсуждение: вопрос, ответы по порядку, поле ответа (с цитатой). Своё — можно удалить.
struct ThreadView: View {
    let threadID: UUID
    let environment: AppEnvironment

    private static let pageSize = 50

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(ReactionStore.self) private var reactions
    @State private var thread: ThreadDetails?
    @State private var posts: [ThreadPost] = []
    @State private var hasMore = true
    @State private var loadError: String?
    @State private var isNotFound = false
    @State private var replyText = ""
    @State private var replyQuote: PostQuote?
    @State private var replyID = UUID()
    @State private var isSending = false
    @State private var sendError: String?
    @State private var confirmsDeleteThread = false
    @FocusState private var isReplyFocused: Bool

    var body: some View {
        Group {
            if let thread {
                content(thread)
            } else if isNotFound {
                EmptyStateView(
                    icon: "bubble.left.and.exclamationmark.bubble.right",
                    title: String(localized: "threads.notFound"),
                    description: String(localized: "threads.notFound.description")
                )
            } else if let loadError {
                EmptyStateView(
                    icon: "wifi.slash",
                    title: String(localized: "threads.failed"),
                    description: loadError,
                    actionTitle: String(localized: "common.retry"),
                    action: { Task { await load() } },
                    style: .error
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonRow() }
                }
                .screenPadding()
                .frame(maxHeight: .infinity, alignment: .top)
                .skeletonLoadingLabel()
            }
        }
        .navigationTitle(Text(verbatim: thread?.placeName ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let thread {
                ToolbarItem(placement: .topBarTrailing) {
                    if thread.isOwn {
                        Menu {
                            Button("threads.delete", systemImage: "trash", role: .destructive) {
                                confirmsDeleteThread = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .accessibilityLabel(Text("profile.menu"))
                        }
                    } else {
                        // Автора обсуждения заблокировали — обсуждение больше не видно.
                        ModerationMenu(target: .thread, targetID: thread.id, author: thread.author, isToolbar: true) {
                            dismiss()
                        }
                    }
                }
            }
        }
        .confirmationDialog("threads.deleteConfirm", isPresented: $confirmsDeleteThread, titleVisibility: .visible) {
            Button("threads.delete", role: .destructive) {
                Task { await deleteThread() }
            }
        }
        .task { await load() }
    }

    private func content(_ thread: ThreadDetails) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(verbatim: thread.title)
                        .font(AppTypography.h3)
                    HStack(spacing: AppSpacing.sm) {
                        Text(verbatim: thread.isOwn ? String(localized: "report.you") : thread.author.label)
                        Text(verbatim: thread.createdAt.formatted(.relative(presentation: .named)))
                        if thread.editedAt != nil {
                            Text("reviews.edited")
                        }
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    Text(verbatim: thread.body)
                        .font(AppTypography.body)
                        .textSelection(.enabled)
                }

                if posts.isEmpty {
                    Text("threads.noReplies")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }

                ForEach(posts) { post in
                    PostRow(
                        post: post,
                        canReply: session.profile != nil,
                        onReply: { quote(post) },
                        onDelete: { Task { await deletePost(post) } },
                        onBlocked: { Task { await load() } }
                    )
                    .onAppear {
                        if post.id == posts.last?.id { Task { await loadMore() } }
                    }
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
        }
        .refreshable { await load() }
        .safeAreaInset(edge: .bottom) {
            if session.profile != nil {
                composer
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if let replyQuote {
                HStack(spacing: AppSpacing.sm) {
                    Rectangle()
                        .fill(AppColors.accent)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("threads.replyingTo \(quoteAuthor(replyQuote))")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.accent)
                        Text(verbatim: replyQuote.body)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        self.replyQuote = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("threads.cancelQuote"))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if let sendError {
                Text(verbatim: sendError)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.destructive)
            }
            HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                TextField("threads.replyPlaceholder", text: $replyText, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($isReplyFocused)
                    .textFieldStyle(.roundedBorder)
                if isSending {
                    ProgressView()
                } else {
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.accent)
                    .disabled(!replyDraft.isValid)
                    .accessibilityLabel(Text("threads.send"))
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(.bar)
    }

    private var replyDraft: PostDraft {
        var draft = PostDraft(threadID: threadID, id: replyID)
        draft.body = replyText
        draft.quote = replyQuote
        return draft
    }

    private func quoteAuthor(_ quote: PostQuote) -> String {
        quote.authorDisplayName ?? quote.authorUsername.map { "@" + $0 } ?? String(localized: "profile.noName")
    }

    private func quote(_ post: ThreadPost) {
        replyQuote = PostQuote(
            postID: post.id,
            authorUsername: post.author.username,
            authorDisplayName: post.author.displayName,
            body: String(post.body.prefix(200))
        )
        isReplyFocused = true
    }

    private func load() async {
        guard let backend = environment.backend else {
            loadError = String(localized: "backend.status.notConfigured")
            return
        }
        do {
            guard let loaded = try await backend.thread(threadID) else {
                isNotFound = true
                return
            }
            let page = try await backend.threadPosts(threadID, limit: Self.pageSize)
            thread = loaded
            posts = page
            hasMore = page.count >= Self.pageSize
            loadError = nil
            seed(page)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard hasMore, let backend = environment.backend, let last = posts.last,
              let page = try? await backend.threadPosts(threadID, limit: Self.pageSize, after: last)
        else { return }
        let known = Set(posts.map(\.id))
        posts += page.filter { !known.contains($0.id) }
        hasMore = page.count >= Self.pageSize
        seed(page)
    }

    private func send() async {
        guard let backend = environment.backend, replyDraft.isValid else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await backend.createPost(replyDraft)
            Task { await NotificationPrimer.shared.offer() }
            replyText = ""
            replyQuote = nil
            replyID = UUID()
            sendError = nil
            // Новый ответ — последний: догружаем всё после последнего показанного.
            hasMore = true
            if posts.isEmpty {
                await load()
            } else {
                await loadMore()
            }
        } catch {
            sendError = CommunityMessage.text(for: error)
        }
    }

    private func deletePost(_ post: ThreadPost) async {
        guard let backend = environment.backend else { return }
        do {
            try await backend.deletePost(post.id)
            posts.removeAll { $0.id == post.id }
        } catch {
            sendError = error.localizedDescription
        }
    }

    private func deleteThread() async {
        guard let backend = environment.backend else { return }
        do {
            try await backend.deleteThread(threadID)
            dismiss()
        } catch {
            sendError = error.localizedDescription
        }
    }

    private func seed(_ page: [ThreadPost]) {
        for post in page {
            reactions.seed(ReactionKey(.post, post.id), post.reactions)
        }
    }
}

/// Ответ в обсуждении: автор, время, цитата, текст, «респект», «Ответить».
struct PostRow: View {
    let post: ThreadPost
    let canReply: Bool
    let onReply: @MainActor () -> Void
    let onDelete: @MainActor () -> Void
    /// Автора заблокировали — перечитать обсуждение.
    var onBlocked: (@MainActor () -> Void)?

    @State private var confirmsDelete = false

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            PersonAvatar(name: post.author.displayName ?? post.author.username, path: post.author.avatarPath, size: 32)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    Text(verbatim: post.isOwn ? String(localized: "report.you") : post.author.label)
                        .font(AppTypography.bodyEmphasis)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: post.createdAt.formatted(.relative(presentation: .named)))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                    if !post.isOwn {
                        ModerationMenu(target: .post, targetID: post.id, author: post.author, onBlocked: onBlocked)
                    }
                }
                if let quote = post.quote {
                    HStack(spacing: AppSpacing.sm) {
                        Rectangle()
                            .fill(AppColors.textTertiary)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(verbatim: quote.authorDisplayName ?? quote.authorUsername.map { "@" + $0 } ?? "")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                            Text(verbatim: quote.body)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(3)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                Text(verbatim: post.body)
                    .font(AppTypography.bodySmall)
                    .textSelection(.enabled)
                HStack(spacing: AppSpacing.lg) {
                    ReactionButton(key: ReactionKey(.post, post.id), isOwn: post.isOwn)
                    if canReply {
                        Button("threads.reply") { onReply() }
                            .buttonStyle(.borderless)
                            .font(AppTypography.caption)
                    }
                    if post.isOwn {
                        Button("threads.deletePost", role: .destructive) { confirmsDelete = true }
                            .buttonStyle(.borderless)
                            .font(AppTypography.caption)
                    }
                    if post.editedAt != nil {
                        Text("reviews.edited")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .confirmationDialog("threads.deletePostConfirm", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("threads.deletePost", role: .destructive) { onDelete() }
        }
    }
}
