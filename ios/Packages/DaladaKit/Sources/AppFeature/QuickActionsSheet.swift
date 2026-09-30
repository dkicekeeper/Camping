import DaladaCore
import DesignTokens
import SwiftUI

/// Быстрые действия из «+». Работает «Начать поездку»; остальное — «Скоро».
struct QuickActionsSheet: View {
    /// Запись уже идёт — вместо старта открываем её.
    let isRecording: Bool
    /// Записывать поездки можно только со входом.
    let canRecord: Bool
    let onStartTrip: @MainActor (TripActivity) -> Void
    let onOpenRecording: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss

    private let soonActions: [(titleKey: LocalizedStringKey, systemImage: String)] = [
        ("quick.checkin", "mappin.circle"),
        ("quick.catch", "fish"),
        ("quick.place", "plus.circle"),
        ("quick.photo", "camera"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isRecording {
                        Button {
                            onOpenRecording()
                            dismiss()
                        } label: {
                            Label("quick.tripInProgress", systemImage: "record.circle")
                                .foregroundStyle(AppColors.destructive)
                        }
                    } else if canRecord {
                        NavigationLink {
                            StartTripView { activity in
                                onStartTrip(activity)
                                dismiss()
                            }
                        } label: {
                            Label("quick.trip", systemImage: "figure.hiking")
                        }
                    } else {
                        HStack {
                            Label("quick.trip", systemImage: "figure.hiking")
                            Spacer()
                            Text("quick.signInRequired")
                                .font(AppTypography.caption)
                        }
                        .foregroundStyle(AppColors.textSecondary)
                    }
                }

                Section {
                    ForEach(soonActions.indices, id: \.self) { index in
                        let action = soonActions[index]
                        HStack {
                            Label(action.titleKey, systemImage: action.systemImage)
                                .font(AppTypography.body)
                            Spacer()
                            Text("common.soon")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .navigationTitle("quick.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("tab.close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    QuickActionsSheet(isRecording: false, canRecord: true, onStartTrip: { _ in }, onOpenRecording: {})
}
