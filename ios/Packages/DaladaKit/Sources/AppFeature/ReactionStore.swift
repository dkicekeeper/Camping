import Backend
import DaladaCore
import DesignTokens
import Observation
import SwiftUI

/// Реакции в памяти — общие для всех экранов (лента, карточка места, поездка, обсуждение):
/// поставил «респект» в ленте — он виден и на странице поездки.
@MainActor
@Observable
final class ReactionStore {
    private(set) var states: [ReactionKey: ReactionState] = [:]
    private var inFlight: Set<ReactionKey> = []
    private let backend: BackendClient?

    init(backend: BackendClient?) {
        self.backend = backend
    }

    func state(for key: ReactionKey) -> ReactionState {
        states[key] ?? ReactionState()
    }

    /// Подгружает реакции к объектам на экране.
    func load(_ keys: [ReactionKey]) async {
        guard let backend, !keys.isEmpty,
              let loaded = try? await backend.reactionSummary(keys)
        else { return }
        for (key, state) in loaded where !inFlight.contains(key) {
            states[key] = state
        }
    }

    /// Состояние, которое пришло вместе со списком (отзывы, ответы в обсуждении).
    func seed(_ key: ReactionKey, _ state: ReactionState) {
        guard !inFlight.contains(key) else { return }
        states[key] = state
    }

    /// Ставит или снимает свою реакцию: сразу на экране, потом на сервере; при ошибке — как было.
    func toggle(_ key: ReactionKey) async {
        guard let backend, !inFlight.contains(key) else { return }
        let before = state(for: key)
        let after = before.toggled()
        states[key] = after
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        do {
            let count = try await backend.setReaction(key, on: after.reacted)
            states[key] = ReactionState(count: count, reacted: after.reacted)
        } catch {
            states[key] = before
        }
    }
}

/// Кнопка реакции: «респект» (рука) или «Полезно» для отзывов. На своё и у гостя — только число.
struct ReactionButton: View {
    enum Style {
        case respect
        case helpful
    }

    let key: ReactionKey
    var isOwn = false
    var style: Style = .respect

    @Environment(ReactionStore.self) private var reactions
    @Environment(SessionStore.self) private var session

    var body: some View {
        let state = reactions.state(for: key)
        Group {
            if isOwn || session.profile == nil {
                if state.count > 0 {
                    Label {
                        Text(verbatim: "\(state.count)")
                    } icon: {
                        Image(systemName: icon(filled: false))
                    }
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityLabel(Text(accessibilityKey(count: state.count)))
                }
            } else {
                Button {
                    Task { await reactions.toggle(key) }
                } label: {
                    Label {
                        if style == .helpful {
                            if state.count > 0 {
                                Text("reaction.helpful \(state.count)")
                            } else {
                                Text("reaction.helpful.zero")
                            }
                        } else if state.count > 0 {
                            Text(verbatim: "\(state.count)")
                        }
                    } icon: {
                        Image(systemName: icon(filled: state.reacted))
                    }
                    .foregroundStyle(state.reacted ? AppColors.accent : AppColors.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(accessibilityKey(count: state.count)))
                .accessibilityAddTraits(state.reacted ? .isSelected : [])
            }
        }
        .font(AppTypography.caption)
    }

    private func icon(filled: Bool) -> String {
        switch style {
        case .respect: filled ? "hand.thumbsup.fill" : "hand.thumbsup"
        case .helpful: filled ? "lightbulb.fill" : "lightbulb"
        }
    }

    private func accessibilityKey(count: Int) -> LocalizedStringKey {
        if style == .helpful {
            return "reaction.helpful.accessibility \(count)"
        }
        return "reaction.respect.accessibility \(count)"
    }
}

extension FeedAuthor {
    /// Имя для подписи: имя, иначе @username.
    var label: String {
        displayName ?? username.map { "@" + $0 } ?? String(localized: "profile.noName")
    }
}
