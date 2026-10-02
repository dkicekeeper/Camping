import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

/// Кнопка «Комментарии» под постом: значок и число; открывает комментарии листом.
struct CommentsButton: View {
    let key: ReactionKey

    @Environment(ReactionStore.self) private var reactions
    @State private var showsComments = false

    var body: some View {
        let count = reactions.commentCount(for: key)
        Button {
            showsComments = true
        } label: {
            Label {
                if count > 0 {
                    Text(verbatim: "\(count)")
                }
            } icon: {
                Image(systemName: "bubble.left")
            }
            .foregroundStyle(AppColors.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .font(AppTypography.caption)
        .accessibilityLabel(Text("comments.accessibility \(count)"))
        .sheet(isPresented: $showsComments) {
            NavigationStack {
                CommentsView(key: key)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// Комментарии поста (поездки, отчёта, отзыва): список, поле ввода. Удалить можно свой комментарий
/// и любой под своим постом (смахнуть влево); у чужих — «Пожаловаться» и «Заблокировать».
struct CommentsView: View {
    let key: ReactionKey

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(ReactionStore.self) private var reactions
    @State private var comments: [PostComment] = []
    @State private var isLoaded = false
    @State private var loadError: String?
    @State private var text = ""
    @State private var draftID = UUID()
    @State private var isSending = false
    @State private var sendError: String?
    @State private var deleteError: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        List {
            if comments.isEmpty {
                if !isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                } else {
                    Text(verbatim: loadError ?? String(localized: "comments.empty"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                        .listRowSeparator(.hidden)
                }
            }
            ForEach(comments) { comment in
                CommentRow(comment: comment, isOwn: comment.author.id == session.profile?.id) {
                    Task { await load() }
                }
                .swipeActions(edge: .trailing) {
                    if comment.canDelete {
                        Button("comments.delete", systemImage: "trash", role: .destructive) {
                            Task { await delete(comment) }
                        }
                    }
                }
                .contextMenu {
                    if comment.canDelete {
                        Button("comments.delete", systemImage: "trash", role: .destructive) {
                            Task { await delete(comment) }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("comments.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("common.close", systemImage: "xmark") { dismiss() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .safeAreaInset(edge: .bottom) {
            composer
        }
        .alert("comments.deleteFailed", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: deleteError ?? "")
        }
    }

    @ViewBuilder
    private var composer: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if session.profile == nil {
                Text("comments.signIn")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                if let sendError {
                    Text(verbatim: sendError)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.destructive)
                }
                HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                    TextField("comments.placeholder", text: $text, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($isFocused)
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
                        .disabled(!draft.isValid)
                        .accessibilityLabel(Text("comments.send"))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(.bar)
    }

    private var draft: CommentDraft {
        CommentDraft(id: draftID, target: key, body: text)
    }

    private func load() async {
        guard let backend = session.backend else {
            isLoaded = true
            return
        }
        do {
            comments = try await backend.postComments(key)
            loadError = nil
            reactions.setCommentCount(comments.count, for: key)
        } catch is CancellationError {
            return
        } catch {
            loadError = CommunityMessage.text(for: error)
        }
        isLoaded = true
    }

    private func send() async {
        guard let backend = session.backend, draft.isValid else { return }
        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            try await backend.addComment(draft)
            text = ""
            draftID = UUID()
            await load()
        } catch {
            sendError = CommunityMessage.text(for: error)
        }
    }

    private func delete(_ comment: PostComment) async {
        guard let backend = session.backend else { return }
        do {
            try await backend.deleteComment(comment.id)
            await load()
        } catch {
            deleteError = CommunityMessage.text(for: error)
        }
    }
}

/// Комментарий: аватар, имя, время, текст; у чужого — «…» (пожаловаться, заблокировать).
private struct CommentRow: View {
    let comment: PostComment
    let isOwn: Bool
    let onBlocked: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            PersonAvatar(name: comment.author.displayName ?? comment.author.username, path: comment.author.avatarPath, size: 32)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack(spacing: AppSpacing.xs) {
                    Text(verbatim: isOwn ? String(localized: "report.you") : comment.author.label)
                        .font(AppTypography.bodyEmphasis)
                        .lineLimit(1)
                    Text(verbatim: comment.createdAt.formatted(.relative(presentation: .named)))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if !isOwn {
                        ModerationMenu(target: .comment, targetID: comment.id, author: comment.author, onBlocked: onBlocked)
                    }
                }
                Text(verbatim: comment.body)
                    .font(AppTypography.bodySmall)
                    .textSelection(.enabled)
            }
        }
    }
}
