import CoreLocation
import DaladaCore
import DesignComponents
import DesignTokens
import MapEngine
import SwiftUI
import UIKit

/// Знакомство при первом запуске: зачем Dalada (места, правила, поездки), геопозиция с объяснением
/// до системного запроса, карта района без сети, вход или «без входа». Показывается один раз,
/// поверх вкладок; вход открывает обычные согласие и выбор username.
struct IntroOnboardingView: View {
    let environment: AppEnvironment
    let onFinish: () -> Void

    @Environment(SessionStore.self) private var session
    @State private var page: Page = .welcome
    @State private var location: GeoPoint?
    @State private var isLocating = false
    @State private var offlineMaps = OfflineMaps.shared

    enum Page: Int, CaseIterable, Hashable {
        case welcome
        case places
        case rules
        case trips
        case location
        case offline
        case signIn
    }

    /// Вошедшему экран входа не нужен.
    private var pages: [Page] {
        session.profile == nil ? Page.allCases : Page.allCases.filter { $0 != .signIn }
    }

    private var suggestedRegion: MapRegion { MapRegions.suggested(near: location) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page.rawValue < Page.location.rawValue {
                    Button("intro.skip") { onFinish() }
                        .font(AppTypography.bodySmall)
                }
            }
            .frame(height: 44)
            .screenPadding()

            TabView(selection: $page) {
                ForEach(pages, id: \.self) { page in
                    content(page)
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            buttons
                .screenPadding()
                .padding(.vertical, AppSpacing.lg)
        }
        .background(AppColors.bgCard.ignoresSafeArea())
        // Вошли прямо здесь — знакомство закончено, дальше согласие и username.
        .onChange(of: session.profile?.id) { _, id in
            if id != nil { onFinish() }
        }
    }

    // MARK: Страницы

    @ViewBuilder
    private func content(_ page: Page) -> some View {
        switch page {
        case .welcome:
            IntroPage(systemImage: "figure.fishing", titleKey: "intro.welcome.title", textKey: "intro.welcome.text") {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label {
                        Text("intro.language \(languageName)")
                    } icon: {
                        Image(systemName: "globe")
                    }
                    .font(AppTypography.bodySmall)
                }
            }
        case .places:
            IntroPage(systemImage: "mappin.and.ellipse", titleKey: "intro.places.title", textKey: "intro.places.text")
        case .rules:
            IntroPage(systemImage: "exclamationmark.shield", titleKey: "intro.rules.title", textKey: "intro.rules.text")
        case .trips:
            IntroPage(
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                titleKey: "intro.trips.title",
                textKey: "intro.trips.text"
            )
        case .location:
            IntroPage(systemImage: "location.circle", titleKey: "intro.location.title", textKey: "intro.location.text")
        case .offline:
            IntroPage(systemImage: "arrow.down.circle", titleKey: "intro.offline.title", textKey: "intro.offline.text") {
                offlineRegionCard
            }
        case .signIn:
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    SignInCard()
                    Text("intro.signIn.guest.hint")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .screenPadding()
                .padding(.top, AppSpacing.xl)
            }
        }
    }

    private var offlineRegionCard: some View {
        let region = suggestedRegion
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(LocalizedStringKey(region.titleKey))
                .font(AppTypography.bodyEmphasis)
            HStack(spacing: AppSpacing.xs) {
                Text("offlineMaps.estimate \(OfflineMapsFormat.size(region.estimatedBytes))")
                switch offlineMaps.state(of: region) {
                case .downloading(let progress, _):
                    Text(verbatim: "·")
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                case .downloaded:
                    Text(verbatim: "·")
                    Label("intro.offline.done", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success)
                default:
                    EmptyView()
                }
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Кнопки

    @ViewBuilder
    private var buttons: some View {
        switch page {
        case .location:
            pair(primaryKey: "intro.location.allow", isWorking: isLocating) {
                Task { await allowLocation() }
            }
        case .offline:
            let region = suggestedRegion
            let canDownload: Bool = {
                switch offlineMaps.state(of: region) {
                case .notDownloaded, .failed, .paused: true
                default: false
                }
            }()
            if canDownload {
                pair(primaryKey: "intro.offline.download", isWorking: false) {
                    offlineMaps.download(region, styleURL: environment.config.mapStyleURL)
                    next()
                }
            } else {
                single(key: "intro.next") { next() }
            }
        case .signIn:
            Button {
                onFinish()
            } label: {
                Text("intro.signIn.guest")
                    .frame(maxWidth: .infinity)
            }
            .secondaryButton()
        default:
            single(key: "intro.next") { next() }
        }
    }

    private func single(key: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(key)
                .frame(maxWidth: .infinity)
        }
        .primaryButton()
    }

    /// Основное действие и «Позже» (просто дальше).
    private func pair(primaryKey: LocalizedStringKey, isWorking: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Button(action: action) {
                Group {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text(primaryKey)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .primaryButton()
            .disabled(isWorking)
            Button {
                next()
            } label: {
                Text("intro.later")
                    .frame(maxWidth: .infinity)
            }
            .secondaryButton()
        }
    }

    // MARK: Действия

    private func next() {
        guard let index = pages.firstIndex(of: page), index + 1 < pages.count else {
            onFinish()
            return
        }
        withAnimation { page = pages[index + 1] }
    }

    /// Системный запрос разрешения; позиция — чтобы предложить ближайший район.
    private func allowLocation() async {
        isLocating = true
        location = await DeviceLocation.current(timeout: .seconds(8))
        isLocating = false
        next()
    }

    private var languageName: String {
        let code = AppConfig.interfaceLanguage
        return Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized(with: Locale(identifier: code))
            ?? code
    }
}

/// Страница знакомства: большой значок, заголовок, текст и что-то под ним.
private struct IntroPage<Accessory: View>: View {
    let systemImage: String
    let titleKey: LocalizedStringKey
    let textKey: LocalizedStringKey
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: systemImage)
                    .font(.system(size: AppIconSize.md * 3))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 140, height: 140)
                    .background(AppColors.accent.opacity(0.12), in: Circle())
                    .padding(.top, AppSpacing.xl)
                VStack(spacing: AppSpacing.sm) {
                    Text(titleKey)
                        .font(AppTypography.h3)
                        .multilineTextAlignment(.center)
                    Text(textKey)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                accessory()
            }
            .screenPadding()
            .padding(.bottom, AppSpacing.xxl)
        }
    }
}

extension IntroPage where Accessory == EmptyView {
    init(systemImage: String, titleKey: LocalizedStringKey, textKey: LocalizedStringKey) {
        self.init(systemImage: systemImage, titleKey: titleKey, textKey: textKey) { EmptyView() }
    }
}
