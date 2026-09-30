import DaladaCore
import DesignComponents
import SwiftUI
import UIKit

/// «Маршрут»: выбор навигатора — установленные приложения (2GIS, Яндекс, Google) и сайты;
/// последний выбранный — первым.
struct RouteButton: View {
    let destination: GeoPoint

    @Environment(\.openURL) private var openURL
    @AppStorage("route.navigator") private var lastNavigator = ""
    @State private var choosing = false

    var body: some View {
        Button {
            choosing = true
        } label: {
            Label("place.card.route", systemImage: "arrow.triangle.turn.up.right.diamond")
                .frame(maxWidth: .infinity)
        }
        .secondaryButton()
        .confirmationDialog("navigator.choose", isPresented: $choosing, titleVisibility: .visible) {
            ForEach(choices) { navigator in
                Button(LocalizedStringKey(navigator.titleKey)) {
                    open(navigator)
                }
            }
        }
    }

    private var choices: [Navigator] {
        let installed = Set(Navigator.allCases.compactMap(\.appScheme).filter { Self.isInstalled($0) })
        let all = Navigator.choices { installed.contains($0) }
        guard let last = all.first(where: { $0.rawValue == lastNavigator }) else { return all }
        return [last] + all.filter { $0 != last }
    }

    private func open(_ navigator: Navigator) {
        lastNavigator = navigator.rawValue
        let installed = navigator.appScheme.map { Self.isInstalled($0) } ?? true
        if let url = navigator.url(to: destination, installed: installed) {
            openURL(url)
        }
    }

    /// Установлено ли приложение — по схеме из `LSApplicationQueriesSchemes` (Info.plist).
    private static func isInstalled(_ scheme: String) -> Bool {
        guard let url = URL(string: "\(scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}
