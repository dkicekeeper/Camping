import Foundation
import Testing
@testable import DaladaCore

@Suite("MapRegions")
struct MapRegionsTests {
    @Test func tileCountMatchesTheTileBuild() {
        // Столько тайлов собирает workflow Map tiles для всего региона (масштабы 0–14).
        #expect(MapRegions.coverage.tileCount(zooms: 0...14) == 185_490)
        #expect(MapRegions.coverage.tileCount(zooms: 0...0) == 1)
    }

    @Test func regionsLieInsideOwnTiles() {
        for region in MapRegions.all {
            #expect(MapRegions.coverage.contains(region.bounds), "\(region.id)")
            #expect(region.bounds.southWest.latitude < region.bounds.northEast.latitude)
            #expect(region.bounds.southWest.longitude < region.bounds.northEast.longitude)
        }
    }

    @Test func regionsStayReasonablySmall() {
        #expect(Set(MapRegions.all.map(\.id)).count == MapRegions.all.count)
        for region in MapRegions.all {
            #expect(region.maxZoom <= 14)
            #expect((500...10_000).contains(region.tileCount), "\(region.id): \(region.tileCount)")
            #expect(region.estimatedBytes < 50 * 1024 * 1024)
        }
        #expect(MapRegions.region(id: "kapshagay")?.titleKey == "offlineMaps.region.kapshagay")
    }

    @Test func estimateCountsRelief() throws {
        // Горы у Алматы: ~31 МБ подложки, ~15 МБ рельефа и горизонталей, 2 МБ шрифтов и значков.
        let mountains = try #require(MapRegions.region(id: "almaty_mountains"))
        let megabytes = Double(mountains.estimatedBytes) / 1024 / 1024
        #expect((45...50).contains(megabytes), "\(megabytes)")
        for region in MapRegions.all {
            #expect(region.estimatedBytes > Int64(region.reliefBytes), "\(region.id)")
        }
    }

    @Test func suggestsRegionByLocation() {
        #expect(MapRegions.suggested(near: nil).id == "almaty_mountains")
        #expect(MapRegions.suggested(near: .almaty).id == "almaty_mountains")
        // Капшагай (Конаев) — внутри района Капшагая.
        #expect(MapRegions.suggested(near: GeoPoint(latitude: 43.87, longitude: 77.07)).id == "kapshagay")
        // Ушарал — у Алаколя, вне всех районов: ближайший по центру.
        #expect(MapRegions.suggested(near: GeoPoint(latitude: 46.17, longitude: 80.94)).id == "alakol")
        // Шымкент — далеко от всех: всё равно какой-то район, не падаем.
        #expect(MapRegions.all.contains(MapRegions.suggested(near: GeoPoint(latitude: 42.32, longitude: 69.59))))
    }
}
