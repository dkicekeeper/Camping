import Foundation
import Testing
@testable import DaladaCore

@Suite("RouteFollowing")
struct RouteFollowingTests {
    /// Прямой маршрут на восток ~1 км: 11 точек через ~100 м.
    let start = GeoPoint(latitude: 43.0, longitude: 77.0)
    var line: [GeoPoint] { (0...10).map { start.destination(distanceM: Double($0) * 100, bearingDegrees: 90) } }

    @Test func progressAlongTheRoute() throws {
        var follower = try #require(RouteFollower(segments: [line]))
        #expect(abs(follower.total - 1000) < 1)

        let first = follower.update(position: start)
        #expect(!first.isApproaching && !first.isOffRoute)
        #expect(first.traveled < 1)

        let middle = follower.update(position: start.destination(distanceM: 450, bearingDegrees: 90))
        #expect(abs(middle.traveled - 450) < 2)
        #expect(abs(middle.remaining - 550) < 2)
        #expect(abs(middle.fraction - 0.45) < 0.01)
    }

    @Test func approachingThenOffRouteWithHysteresis() throws {
        var follower = try #require(RouteFollower(segments: [line]))
        let middle = start.destination(distanceM: 500, bearingDegrees: 90)

        // Ещё не на маршруте — «до маршрута», без предупреждения.
        let far = follower.update(position: middle.destination(distanceM: 500, bearingDegrees: 0))
        #expect(far.isApproaching && !far.isOffRoute)
        #expect(abs(far.distanceToRoute - 500) < 5)

        _ = follower.update(position: middle)
        #expect(follower.update(position: middle.destination(distanceM: 100, bearingDegrees: 0)).isOffRoute)
        // Между порогами — всё ещё не на маршруте, затем вернулся.
        #expect(follower.update(position: middle.destination(distanceM: 45, bearingDegrees: 0)).isOffRoute)
        #expect(!follower.update(position: middle.destination(distanceM: 30, bearingDegrees: 0)).isOffRoute)
        // На пороге входа, но с плохой точностью GPS — не сход.
        #expect(!follower.update(position: middle.destination(distanceM: 80, bearingDegrees: 0), accuracy: 40).isOffRoute)
    }

    @Test func finishAtTheEnd() throws {
        var follower = try #require(RouteFollower(segments: [line]))
        _ = follower.update(position: start)
        let end = follower.update(position: line[10])
        #expect(end.isFinished)
        #expect(end.remaining == 0)
    }

    @Test func outAndBackKeepsTheDirection() throws {
        // Туда и обратно по одной линии: начало и конец совпадают.
        var follower = try #require(RouteFollower(segments: [line + line.reversed()]))
        #expect(abs(follower.total - 2000) < 2)

        let begin = follower.update(position: start)
        #expect(begin.traveled < 1)
        #expect(!begin.isFinished)

        // Идём до конца и обратно шагами по 50 м.
        var last = begin
        for step in 1...40 {
            let distance = step <= 20 ? Double(step) * 50 : Double(40 - step) * 50
            last = follower.update(position: start.destination(distanceM: distance, bearingDegrees: 90))
            #expect(abs(last.traveled - Double(step) * 50) < 5, "шаг \(step): \(last.traveled)")
        }
        #expect(last.isFinished)
    }

    @Test func reversedRouteStartsAtTheOtherEnd() throws {
        var follower = try #require(RouteFollower(segments: [line], reversed: true))
        let progress = follower.update(position: line[10])
        #expect(progress.traveled < 1)
        #expect(abs(progress.remaining - 1000) < 2)
    }

    @Test func tooShortTracksCannotBeFollowed() {
        #expect(RouteFollower(segments: []) == nil)
        #expect(RouteFollower(segments: [[start, start]]) == nil)
    }
}
