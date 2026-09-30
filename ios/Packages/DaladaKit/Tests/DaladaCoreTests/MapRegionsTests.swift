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
            #expect((500...5_000).contains(region.tileCount), "\(region.id): \(region.tileCount)")
            #expect(region.estimatedBytes < 100 * 1024 * 1024)
        }
        #expect(MapRegions.region(id: "kapshagay")?.titleKey == "offlineMaps.region.kapshagay")
    }
}
