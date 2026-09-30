import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

/// «Аккаунт»: кто вошёл, «Выйти», «Удалить аккаунт».
struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var confirmsDelete = false
    @State private var deleteError: String?
    @State private var showsDeleteError = false

    var body: some View {
        List {
            if let profile = session.profile {
                Section {
                    LabeledContent("account.username") {
                        Text(verbatim: profile.username.map { "@" + $0 } ?? "—")
                    }
                    if let name = profile.displayName, !name.isEmpty {
                        LabeledContent("account.name") {
                            Text(verbatim: name)
                        }
                    }
                }
            }

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
        }
        .navigationTitle("account.title")
        .navigationBarTitleDisplayMode(.inline)
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

    private func deleteAccount() async {
        if let error = await session.deleteAccount() {
            deleteError = error
            showsDeleteError = true
        } else {
            dismiss()
        }
    }
}
