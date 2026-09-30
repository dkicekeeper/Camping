import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity записи поездки: экран блокировки и Dynamic Island.
///
/// Тексты (вид поездки, дистанция, «Пауза») готовит приложение на своём языке — расширению
/// не нужны свои переводы. Время идёт само (`Text(timerInterval:)`), без обновлений из приложения.
public struct TripActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        /// «12,4 км».
        public var distanceText: String
        /// «На паузе» или `nil`, пока запись идёт.
        public var statusText: String?

        public init(distanceText: String, statusText: String?) {
            self.distanceText = distanceText
            self.statusText = statusText
        }
    }

    /// «Рыбалка».
    public var title: String
    public var systemImage: String
    public var startedAt: Date

    public init(title: String, systemImage: String, startedAt: Date) {
        self.title = title
        self.systemImage = systemImage
        self.startedAt = startedAt
    }
}

/// Виджет для расширения `DaladaWidgets`.
public struct TripLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.attributes.systemImage)
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title)
                        .font(.headline)
                    if let status = context.state.statusText {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    ElapsedText(startedAt: context.attributes.startedAt)
                        .font(.title3.monospacedDigit())
                    Text(context.state.distanceText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: context.attributes.systemImage)
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.distanceText)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        ElapsedText(startedAt: context.attributes.startedAt)
                            .font(.title2.monospacedDigit())
                        Spacer(minLength: 0)
                        if let status = context.state.statusText {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.systemImage)
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(context.state.distanceText)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.attributes.systemImage)
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// Время с начала поездки, идёт само.
struct ElapsedText: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .multilineTextAlignment(.trailing)
    }
}
