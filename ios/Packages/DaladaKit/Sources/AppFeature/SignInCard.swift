import AuthenticationServices
import DesignTokens
import SwiftUI

/// Карточка входа для гостя: Apple (основная кнопка по правилам App Store) и Google.
struct SignInCard: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme

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
}
