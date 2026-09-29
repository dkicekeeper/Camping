import DesignComponents
import DesignTokens
import SwiftUI

/// Заглушка раздела, который появится в следующих этапах: иконка, заголовок, пояснение.
/// Тексты передаются уже локализованными (EmptyStateView принимает `String`).
public struct PlaceholderScreen: View {
    private let icon: String
    private let title: String
    private let description: String

    public init(icon: String, title: String, description: String) {
        self.icon = icon
        self.title = title
        self.description = description
    }

    public var body: some View {
        EmptyStateView(icon: icon, title: title, description: description)
            .padding(AppSpacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PlaceholderScreen(icon: "mappin.and.ellipse", title: "Места", description: "Скоро здесь появятся места.")
}
