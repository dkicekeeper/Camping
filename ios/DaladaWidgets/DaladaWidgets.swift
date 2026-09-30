import SwiftUI
import TripLiveActivity
import WidgetKit

/// Расширение виджетов Dalada. Пока только Live Activity записи поездки.
@main
struct DaladaWidgets: WidgetBundle {
    var body: some Widget {
        TripLiveActivityWidget()
    }
}
