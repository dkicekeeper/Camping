import Foundation
import Network

/// Появление сети — сигнал отправить офлайн-очередь.
enum NetworkMonitor {
    /// Событие на каждый переход «нет сети → есть сеть».
    static func becameAvailable() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            let last = LastStatus()
            monitor.pathUpdateHandler = { path in
                // Вызывается последовательно на очереди монитора.
                let satisfied = path.status == .satisfied
                if satisfied, last.satisfied == false {
                    continuation.yield()
                }
                last.satisfied = satisfied
            }
            let holder = MonitorHolder(monitor: monitor)
            continuation.onTermination = { _ in holder.monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "app.dalada.network"))
        }
    }

    /// Последнее состояние сети; меняется только на очереди монитора.
    private final class LastStatus: @unchecked Sendable {
        var satisfied: Bool?
    }

    private final class MonitorHolder: @unchecked Sendable {
        let monitor: NWPathMonitor
        init(monitor: NWPathMonitor) { self.monitor = monitor }
    }
}
