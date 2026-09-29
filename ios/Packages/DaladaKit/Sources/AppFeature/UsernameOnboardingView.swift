import DaladaCore
import DesignTokens
import SwiftUI

/// Выбор username после первого входа. Проверка формата — сразу, занятости — на сервере
/// через 0,4 с после последнего ввода.
struct UsernameOnboardingView: View {
    @Environment(SessionStore.self) private var session

    @State private var username = ""
    @State private var status: Status = .idle
    @State private var saveError: String?
    @FocusState private var isFocused: Bool

    enum Status: Equatable {
        case idle
        case invalidFormat
        case checking
        case available
        case unavailable
        case failed
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text("onboarding.username.subtitle")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)

                HStack(spacing: AppSpacing.xs) {
                    Text(verbatim: "@")
                        .foregroundStyle(AppColors.textSecondary)
                    TextField("onboarding.username.placeholder", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .textContentType(.username)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }
                }
                .font(AppTypography.bodyEmphasis)
                .padding(AppSpacing.md)
                .background(AppColors.bgMuted, in: RoundedRectangle(cornerRadius: AppRadius.md))

                statusLine
                    .font(AppTypography.caption)

                Spacer()

                Button {
                    Task { await save() }
                } label: {
                    Text("onboarding.username.save")
                        .frame(maxWidth: .infinity)
                }
                .primaryButton(disabled: status != .available || session.isWorking)
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.xl)
            .navigationTitle("onboarding.username.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("profile.signOut") {
                        Task { await session.signOut() }
                    }
                }
            }
            .task(id: username) { await validate() }
            .onAppear { isFocused = true }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .idle:
            Text(verbatim: " ")
        case .invalidFormat:
            Label("onboarding.username.invalid", systemImage: "xmark.circle")
                .foregroundStyle(AppColors.destructive)
        case .checking:
            Label("onboarding.username.checking", systemImage: "hourglass")
                .foregroundStyle(AppColors.textSecondary)
        case .available:
            Label("onboarding.username.available", systemImage: "checkmark.circle.fill")
                .foregroundStyle(AppColors.success)
        case .unavailable:
            Label("onboarding.username.taken", systemImage: "xmark.circle.fill")
                .foregroundStyle(AppColors.destructive)
        case .failed:
            Label("onboarding.username.failed", systemImage: "wifi.slash")
                .foregroundStyle(AppColors.warning)
        }
        if let saveError {
            Text(saveError)
                .foregroundStyle(AppColors.destructive)
        }
    }

    /// Вызывается при каждом изменении текста; предыдущая проверка отменяется (`task(id:)`).
    private func validate() async {
        saveError = nil
        let candidate = UsernameRules.normalized(username)
        guard !candidate.isEmpty else {
            status = .idle
            return
        }
        guard UsernameRules.isValidFormat(candidate) else {
            status = .invalidFormat
            return
        }
        status = .checking
        do {
            try await Task.sleep(for: .milliseconds(400))
        } catch {
            return
        }
        guard let backend = session.backend else { return }
        do {
            status = try await backend.isUsernameAvailable(candidate) ? .available : .unavailable
        } catch is CancellationError {
            return
        } catch {
            status = .failed
        }
    }

    private func save() async {
        guard status == .available else { return }
        saveError = await session.saveUsername(UsernameRules.normalized(username))
        if saveError != nil { status = .idle }
    }
}
