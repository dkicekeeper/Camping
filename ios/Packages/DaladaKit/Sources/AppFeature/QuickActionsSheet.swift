import DesignTokens
import SwiftUI

/// Быстрые действия из «+». Пока все помечены «Скоро» — появятся в этапах M1–M3.
struct QuickActionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let actions: [(titleKey: LocalizedStringKey, systemImage: String)] = [
        ("quick.trip", "figure.hiking"),
        ("quick.checkin", "mappin.circle"),
        ("quick.catch", "fish"),
        ("quick.place", "plus.circle"),
        ("quick.photo", "camera"),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(actions.indices, id: \.self) { index in
                    let action = actions[index]
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
    QuickActionsSheet()
}
