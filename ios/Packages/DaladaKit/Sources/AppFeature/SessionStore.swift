import AuthenticationServices
import Backend
import CryptoKit
import DaladaCore
import Foundation
import Observation
import Persistence

/// Состояние входа и свой профиль. Один экземпляр на приложение, передаётся через `.environment`.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        /// Ждём первое событие от Supabase Auth.
        case loading
        /// Без входа: карта и публичные места доступны, создавать ничего нельзя.
        case guest
        /// Вошёл, но ещё не выбрал username — показываем онбординг.
        case needsUsername(UserProfile)
        case signedIn(UserProfile)
        /// Вошёл, но профиль не загрузился и сохранённого нет (например, первый запуск без сети).
        case profileUnavailable(String)
    }

    private(set) var state: State = .loading
    private(set) var isWorking = false
    var errorMessage: String?

    let backend: BackendClient?
    /// Профиль на случай запуска без сети.
    private let cache: CacheStore?
    private var appleNonce: String?

    init(backend: BackendClient?, cache: CacheStore? = nil) {
        self.backend = backend
        self.cache = cache
    }

    var profile: UserProfile? {
        switch state {
        case .needsUsername(let profile), .signedIn(let profile): profile
        case .loading, .guest, .profileUnavailable: nil
        }
    }

    var needsUsername: Bool {
        if case .needsUsername = state { true } else { false }
    }

    /// Для `.fullScreenCover`: онбординг закрывается сам, когда username сохранён.
    var isUsernameOnboardingPresented: Bool {
        get { needsUsername }
        set {}
    }

    /// Для `.alert`: закрытие алерта сбрасывает ошибку.
    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    /// Слушает вход и выход до закрытия приложения. Вызывается из `.task` корневого экрана.
    func start() async {
        guard let backend else {
            state = .guest
            return
        }
        for await userID in backend.authChanges() {
            if userID == nil {
                state = .guest
            } else {
                await reloadProfile()
            }
        }
    }

    func reloadProfile() async {
        guard let backend else { return }
        do {
            let profile = try await backend.myProfile()
            apply(profile)
            try? await cache?.save(profile, for: .profile(profile.id))
        } catch {
            // Нет сети — работаем с сохранённым профилем: чекины уйдут в очередь.
            if let userID = backend.currentUserID,
               let cached = try? await cache?.load(UserProfile.self, for: .profile(userID)) {
                apply(cached)
            } else {
                state = .profileUnavailable(error.localizedDescription)
            }
        }
    }

    private func apply(_ profile: UserProfile) {
        state = profile.username == nil ? .needsUsername(profile) : .signedIn(profile)
    }

    // MARK: Apple

    /// Настраивает запрос Sign in with Apple: имя и хеш nonce (исходный nonce уходит в Supabase).
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = SecureRandom.string()
        appleNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = Self.sha256(nonce)
    }

    /// Разбирает результат кнопки Apple синхронно и запускает вход с уже извлечёнными строками.
    func handleAppleCompletion(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = String(localized: "auth.error.generic")
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce
            else {
                errorMessage = String(localized: "auth.error.generic")
                return
            }
            let fullName = credential.fullName
                .map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task { await signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName) }
        }
    }

    private func signInWithApple(idToken: String, nonce: String, fullName: String?) async {
        guard let backend else { return }
        await perform {
            try await backend.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
        }
        // Имя сохраняется после входа — перечитываем профиль, чтобы оно появилось сразу.
        if backend.isSignedIn { await reloadProfile() }
    }

    // MARK: Google, выход

    func signInWithGoogle() async {
        guard let backend else { return }
        await perform { try await backend.signInWithGoogle() }
    }

    func signOut() async {
        guard let backend else { return }
        let userID = backend.currentUserID
        await perform { try await backend.signOut() }
        // Сохранённые данные аккаунта на телефоне не остаются. Неотправленные чекины остаются
        // в очереди и уйдут, когда этот пользователь войдёт снова.
        if let userID, !backend.isSignedIn {
            try? await cache?.removeUserData(userID)
        }
    }

    // MARK: Username

    /// Сохраняет username. Возвращает текст ошибки для поля ввода или `nil` при успехе.
    func saveUsername(_ username: String) async -> String? {
        guard let backend else { return String(localized: "auth.error.generic") }
        isWorking = true
        defer { isWorking = false }
        do {
            let profile = try await backend.updateProfile(username: username)
            state = .signedIn(profile)
            try? await cache?.save(profile, for: .profile(profile.id))
            return nil
        } catch ProfileUpdateError.usernameTaken {
            return String(localized: "onboarding.username.taken")
        } catch ProfileUpdateError.usernameInvalid {
            return String(localized: "onboarding.username.invalid")
        } catch {
            return CommunityMessage.text(for: error)
        }
    }

    // MARK: Помощники

    private func perform(_ operation: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            if !Self.isUserCancellation(error) {
                errorMessage = String(localized: "auth.error.generic")
            }
        }
    }

    private static func isUserCancellation(_ error: any Error) -> Bool {
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin { return true }
        if let error = error as? ASAuthorizationError, error.code == .canceled { return true }
        return error is CancellationError
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
