import Foundation
import Testing
@testable import DaladaCore

@Suite("PlacePhotos")
struct PlacePhotosTests {
    static let json = """
    [{
      "id": "eeeeeeee-0000-0000-0000-000000000002",
      "checkin_id": "cccccccc-0000-0000-0000-000000000001",
      "catch_id": "dddddddd-0000-0000-0000-000000000001",
      "path": "22222222-2222-2222-2222-222222222222/eeeeeeee-0000-0000-0000-000000000002.jpg",
      "thumb_path": "22222222-2222-2222-2222-222222222222/eeeeeeee-0000-0000-0000-000000000002_thumb.jpg",
      "width": 1200, "height": 1600,
      "at": "2026-10-01T05:12:33.123456+00:00",
      "author_id": "22222222-2222-2222-2222-222222222222",
      "author_username": "friend_f", "author_display_name": null, "author_avatar_path": null,
      "is_own": false
    }]
    """

    @Test func decodesServerRows() throws {
        let photos = try PlaceDiscoveryTests.decoder().decode([PlacePhoto].self, from: Data(Self.json.utf8))
        let photo = try #require(photos.first)
        #expect(photo.isCatch)
        #expect(photo.authorName == "@friend_f")
        #expect(photo.thumbnailPath.hasSuffix("_thumb.jpg"))
        #expect(photo.width == 1200 && photo.height == 1600)
        #expect(!photo.isOwn)

        let cached = try JSONDecoder().decode([PlacePhoto].self, from: JSONEncoder().encode(photos))
        #expect(cached == photos)
    }

    @Test func authorNamePrefersDisplayName() {
        let photo = PlacePhoto(
            id: UUID(), checkinID: UUID(), path: "a.jpg", thumbnailPath: "a_thumb.jpg", at: Date(),
            author: FeedAuthor(id: UUID(), username: "f", displayName: "Фарида")
        )
        #expect(photo.authorName == "Фарида")
        #expect(!photo.isCatch)
        #expect(PlacePhotoKind.allCases.map(\.rawValue) == ["all", "catches", "place"])
    }
}
