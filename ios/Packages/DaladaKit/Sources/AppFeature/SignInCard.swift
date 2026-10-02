import AuthenticationServices
import DesignComponents
import DesignTokens
import SwiftUI

/// Карточка входа для гостя: Apple (основная кнопка по правилам App Store), Google и — свёрнуто —
/// почта с паролем для аккаунтов, которые заводит редакция (демо-доступ для проверки Apple).
struct SignInCard: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsEmail = false
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        @Bindable var session = session
        VStack(spacing: AppSpacing.lg) {
            VStack(spacing: AppSpacing.sm) {
                Text("auth.title")
                    .font(AppTypography.h4)
                    .multilineTextAlignment(.center)
                Text("auth.subtitle")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            SignInWithAppleButton(.signIn) { request in
                session.prepareAppleRequest(request)
            } onCompletion: { result in
                session.handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(Capsule())

            Button {
                Task { await session.signInWithGoogle() }
            } label: {
                Label("auth.google", systemImage: "g.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .secondaryButton()

            if showsEmail {
                emailForm
            } else {
                Button("auth.email.open") {
                    withAnimation { showsEmail = true }
                }
                .font(AppTypography.bodySmall)
            }

            if session.isWorking {
                ProgressView()
            }
        }
        .disabled(session.isWorking)
        .cardContentPadding()
        .cardStyle()
        .alert("auth.error.title", isPresented: $session.isShowingError) {
            Button("common.ok") {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    /// Почта и пароль: только вход, регистрации здесь нет.
    private var emailForm: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormTextField(
                text: $email,
                placeholder: String(localized: "auth.email.address"),
                keyboardType: .emailAddress
            )
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            SecureField(String(localized: "auth.email.password"), text: $password)
                .textContentType(.password)
                .font(AppTypography.body)
                .padding(AppSpacing.lg)
                .background(AppColors.bgCard.opacity(0.5))
                .clipShape(.rect(cornerRadius: AppRadius.lg))

            Button {
                Task { await session.signInWithEmail(email, password: password) }
            } label: {
                Text("auth.email.signIn")
                    .frame(maxWidth: .infinity)
            }
            .secondaryButton()
            .disabled(!email.contains("@") || password.count < 8)

            Text("auth.email.hint")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
