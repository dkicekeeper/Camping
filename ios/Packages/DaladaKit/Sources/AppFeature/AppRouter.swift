import DesignComponents
import DesignTokens
import Observation
import SwiftUI

/// Вкладки приложения: Главная, Карта, Места, Лайфхаки, Профиль.
enum AppTab: Hashable {
    case home
    case map
    case places
    case lifehacks
    case profile
}

/// Навигация между вкладками и общие действия разделов. Отдельной вкладки «+» нет: добавления —
/// там, где они нужны (поездка — с карты и «Главной», чекин — из карточки места, место — с карты).
@MainActor
@Observable
final class AppRouter {
    var selection: AppTab = .home
    /// Лист выбора вида поездки (гостю — вход).
    var showsTripStart = false
    /// Экран идущей записи.
    var showsRecording = false

    /// «Начать поездку»: если запись уже идёт — открыть её, иначе выбрать вид поездки.
    func startTrip(isRecording: Bool) {
        if isRecording {
            showsRecording = true
        } else {
            showsTripStart = true
        }
    }
}

/// Кнопка «Начать поездку»; во время записи — «Идёт поездка» (открывает запись).
struct StartTripButton: View {
    /// Только значок — для панели навигации.
    var isCompact = false

    @Environment(AppRouter.self) private var router
    @Environment(TripRecorder.self) private var recorder

    var body: some View {
        Button {
            router.startTrip(isRecording: recorder.isActive)
        } label: {
            if isCompact {
                Image(systemName: recorder.isActive ? "record.circle" : "figure.hiking")
                    .accessibilityLabel(Text(titleKey))
            } else {
                Label(titleKey, systemImage: recorder.isActive ? "record.circle" : "figure.hiking")
            }
        }
    }

    private var titleKey: LocalizedStringKey {
        LocalizedStringKey(recorder.isActive ? "quick.tripInProgress" : "quick.trip")
    }
}
