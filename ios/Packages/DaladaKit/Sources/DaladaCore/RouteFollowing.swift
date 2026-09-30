import Foundation

/// Где человек относительно маршрута, по которому идёт.
public struct RouteProgress: Equatable, Sendable {
    /// Расстояние от человека до линии маршрута, м.
    public let distanceToRoute: Double
    /// Пройдено по маршруту от начала до ближайшей точки, м.
    public let traveled: Double
    /// Осталось до конца маршрута, м.
    public let remaining: Double
    public let total: Double
    /// Ещё не выходил на маршрут: показываем «до маршрута», без предупреждений.
    public let isApproaching: Bool
    /// Сошёл с маршрута (после того как был на нём).
    public let isOffRoute: Bool
    /// Дошёл до конца.
    public let isFinished: Bool

    public var fraction: Double { total > 0 ? min(max(traveled / total, 0), 1) : 0 }
}

/// Следование по треку: ближайшая точка маршрута, пройдено и осталось, сход с маршрута.
///
/// Маршрут туда-обратно по одной дороге неоднозначен: одна и та же точка — и в начале, и в конце.
/// Поэтому из почти одинаково близких участков берётся тот, что ближе к прошлому положению на
/// маршруте (в начале — к старту), и шаг назад по маршруту «дороже» шага вперёд: после разворота
/// в дальней точке человек идёт по обратной половине, а не «возвращается» по первой.
public struct RouteFollower: Sendable {
    /// Дальше — сошёл с маршрута; ближе — вернулся (разные пороги, чтобы не мигало на границе).
    public static let offRouteEnterM = 60.0
    public static let offRouteExitM = 35.0
    /// Ближе к концу маршрута — дошёл.
    public static let finishRadiusM = 40.0
    /// Участки не дальше лучшего на столько метров считаются «одинаково близкими».
    static let ambiguityM = 25.0
    /// Точность GPS учитывается не больше чем на столько.
    static let maxAccuracyAllowanceM = 50.0

    public let points: [GeoPoint]
    /// Расстояние по маршруту от начала до каждой точки.
    let cumulative: [Double]
    public var total: Double { cumulative.last ?? 0 }

    public private(set) var hasJoined = false
    public private(set) var isOffRoute = false
    public private(set) var traveled = 0.0

    /// Маршрут из отрезков трека (скрытые участки чужого трека соединяются прямой);
    /// `reversed` — пройти в обратную сторону. `nil`, если в треке меньше двух точек.
    public init?(segments: [[GeoPoint]], reversed: Bool = false) {
        var line = segments.flatMap { $0 }
        if reversed { line.reverse() }
        // Повторы одной точки не нужны: у отрезка нулевой длины нет направления.
        line = line.reduce(into: []) { result, point in
            if result.last != point { result.append(point) }
        }
        guard line.count >= 2 else { return nil }
        points = line
        var sums = [0.0]
        for index in 1..<line.count {
            sums.append(sums[index - 1] + line[index - 1].distance(to: line[index]))
        }
        cumulative = sums
    }

    /// Новая позиция человека. `accuracy` — погрешность GPS, м.
    public mutating func update(position: GeoPoint, accuracy: Double = 0) -> RouteProgress {
        let candidates = (0..<(points.count - 1)).map { projection(of: position, onSegment: $0) }
        let closest = candidates.map(\.distance).min() ?? 0
        // Где человек на маршруте: до выхода на маршрут — ближайшая точка (из равных — ближе к
        // старту), потом — из почти одинаково близких та, что ближе к прошлому положению.
        let expected = hasJoined ? traveled : 0
        let tolerance = hasJoined ? Self.ambiguityM : 1
        let best = candidates
            .filter { $0.distance <= closest + tolerance }
            .min { Self.jumpCost($0.along, from: expected) < Self.jumpCost($1.along, from: expected) } ?? candidates[0]

        let effective = max(0, closest - min(max(accuracy, 0), Self.maxAccuracyAllowanceM))
        if effective <= Self.offRouteExitM {
            hasJoined = true
            isOffRoute = false
        } else if hasJoined && effective > Self.offRouteEnterM {
            isOffRoute = true
        }
        if hasJoined {
            traveled = best.along
        }
        let remaining = max(total - traveled, 0)
        let finished = hasJoined && !isOffRoute
            && remaining <= Self.finishRadiusM + min(max(accuracy, 0), Self.maxAccuracyAllowanceM)
        return RouteProgress(
            distanceToRoute: closest,
            traveled: traveled,
            remaining: finished ? 0 : remaining,
            total: total,
            isApproaching: !hasJoined,
            isOffRoute: isOffRoute,
            isFinished: finished
        )
    }

    /// Насколько «далеко» перескочить по маршруту с `from` на `along`: назад — втрое дороже.
    static func jumpCost(_ along: Double, from: Double) -> Double {
        along >= from ? along - from : (from - along) * 3
    }

    /// Ближайшая к `position` точка отрезка `index` (в метрах, на плоскости вокруг позиции —
    /// на расстояниях маршрута погрешность ничтожна).
    func projection(of position: GeoPoint, onSegment index: Int) -> (distance: Double, along: Double) {
        let a = points[index]
        let b = points[index + 1]
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(position.latitude * .pi / 180)
        let ax = (a.longitude - position.longitude) * metersPerDegreeLon
        let ay = (a.latitude - position.latitude) * metersPerDegreeLat
        let bx = (b.longitude - position.longitude) * metersPerDegreeLon
        let by = (b.latitude - position.latitude) * metersPerDegreeLat
        let dx = bx - ax
        let dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared > 0 ? min(max(-(ax * dx + ay * dy) / lengthSquared, 0), 1) : 0
        let px = ax + t * dx
        let py = ay + t * dy
        let segmentLength = cumulative[index + 1] - cumulative[index]
        return (distance: (px * px + py * py).squareRoot(), along: cumulative[index] + t * segmentLength)
    }
}
