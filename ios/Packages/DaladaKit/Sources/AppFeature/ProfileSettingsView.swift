import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

/// Настройки профиля (нажатие на шапку в «Профиле»): имя, username, зоны приватности, уведомления,
/// выход, удаление аккаунта, документы и поддержка.
struct ProfileSettingsView: View {
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var name = ""
    @State private var nameError: String?
    @State private var confirmsDelete = false
    @State private var deleteError: String?
    @State private var showsDeleteError = false

    var body: some View {
        List {
            if let profile = session.profile {
                Section {
                    TextField("account.name.placeholder", text: $name)
                        .textContentType(.name)
                        .submitLabel(.done)
                        .onSubmit { Task { await saveName() } }
                    LabeledContent("account.username") {
                        Text(verbatim: profile.username.map { "@" + $0 } ?? "—")
                    }
                } header: {
                    Text("account.name")
                } footer: {
                    if let nameError {
                        Text(verbatim: nameError)
                            .foregroundStyle(AppColors.destructive)
                    } else if trimmedName.count > SessionStore.displayNameLimit {
                        Text("place.info.tooLong \(SessionStore.displayNameLimit)")
                            .foregroundStyle(AppColors.destructive)
                    }
                }
            }

            Section {
                NavigationLink {
                    PrivacyZonesView(environment: environment)
                } label: {
                    Label("privacyZones.title", systemImage: "house.circle")
                }
            } footer: {
                Text("profile.settings.privacyZonesFooter")
            }

            NotificationsSection()

            Section {
                Button("profile.signOut", systemImage: "rectangle.portrait.and.arrow.right") {
                    Task {
                        await session.signOut()
                        dismiss()
                    }
                }
                .disabled(session.isWorking)
            }

            Section {
                Button(role: .destructive) {
                    confirmsDelete = true
                } label: {
                    if session.isWorking {
                        HStack(spacing: AppSpacing.sm) {
                            ProgressView()
                            Text("account.delete.progress")
                        }
                    } else {
                        Label("account.delete", systemImage: "trash")
                    }
                }
                .disabled(session.isWorking)
            } footer: {
                Text("account.delete.footer")
            }

            LegalLinksSection()
        }
        .navigationTitle("profile.settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canSaveName {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        Task { await saveName() }
                    }
                    .disabled(session.isWorking)
                }
            }
        }
        .onAppear { name = session.profile?.displayName ?? "" }
        .onChange(of: name) { _, _ in nameError = nil }
        .confirmationDialog("account.delete.confirm", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("account.delete.confirmButton", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("account.delete.message")
        }
        .alert("account.delete.failed", isPresented: $showsDeleteError) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: deleteError ?? "")
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Имя изменилось, не пустое и не длиннее предела.
    private var canSaveName: Bool {
        !trimmedName.isEmpty
            && trimmedName.count <= SessionStore.displayNameLimit
            && trimmedName != (session.profile?.displayName ?? "")
    }

    private func saveName() async {
        guard canSaveName else { return }
        if let error = await session.updateDisplayName(trimmedName) {
            nameError = error
        } else {
            name = session.profile?.displayName ?? trimmedName
        }
    }

    private func deleteAccount() async {
        if let error = await session.deleteAccount() {
            deleteError = error
            showsDeleteError = true
        } else {
            dismiss()
        }
    }
}
