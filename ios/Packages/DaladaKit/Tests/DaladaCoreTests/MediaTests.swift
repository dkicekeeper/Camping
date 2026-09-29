import Foundation
import Testing
@testable import DaladaCore

@Suite("Media")
struct MediaTests {
    private let owner = UUID(uuidString: "11111111-AAAA-1111-1111-111111111111")!
    private let media = UUID(uuidString: "EEEEEEEE-0000-0000-0000-00000000000A")!

    private func photo(_ id: UUID = UUID()) -> PhotoDraft {
        PhotoDraft(id: id, full: Data([1]), thumbnail: Data([2]), width: 1600, height: 1200)
    }

    @Test func pathsAreLowercaseLikeInTheDatabase() {
        #expect(MediaPath.full(owner: owner, media: media)
            == "11111111-aaaa-1111-1111-111111111111/eeeeeeee-0000-0000-0000-00000000000a.jpg")
        #expect(MediaPath.thumbnail(owner: owner, media: media)
            == "11111111-aaaa-1111-1111-111111111111/eeeeeeee-0000-0000-0000-00000000000a_thumb.jpg")
    }

    @Test func decodesReportMedia() throws {
        let json = """
        [{"checkin_id": "cccccccc-0000-0000-0000-000000000001",
          "author_id": "11111111-1111-1111-1111-111111111111",
          "author_username": null, "author_display_name": null,
          "at": "2026-09-30T10:00:00Z", "verified": false, "conditions": {}, "note": null,
          "is_own": true, "catches": [],
          "media": [{"id": "eeeeeeee-0000-0000-0000-000000000001", "catch_id": null,
                     "path": "a/e.jpg", "thumb_path": "a/e_thumb.jpg", "width": 1600, "height": 1200}]}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try #require(try decoder.decode([PlaceReport].self, from: Data(json.utf8)).first)
        #expect(report.media.count == 1)
        #expect(report.media[0].thumbnailPath == "a/e_thumb.jpg")
        #expect(report.media[0].catchID == nil)
        #expect(report.media[0].width == 1600)
    }

    @Test func reportWithoutMediaKeyDecodes() throws {
        let json = """
        {"checkin_id": "cccccccc-0000-0000-0000-000000000001",
         "author_id": "11111111-1111-1111-1111-111111111111",
         "at": "2026-09-30T10:00:00Z", "verified": true, "conditions": {"bite": "good"},
         "is_own": false, "catches": []}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(PlaceReport.self, from: Data(json.utf8))
        #expect(report.media.isEmpty)
        #expect(report.authorUsername == nil)
        #expect(report.conditions.bite == .good)
    }

    @Test func uploadsCheckinPhotosFirstThenCatchPhotos() {
        let checkinPhoto = photo()
        let catchPhoto = photo()
        let withPhoto = CatchDraft(speciesID: "pike", photo: catchPhoto)
        let withoutPhoto = CatchDraft(speciesID: "perch")
        let draft = CheckinDraft(placeID: UUID(), catches: [withoutPhoto, withPhoto], photos: [checkinPhoto])
        #expect(draft.photoUploads == [
            PhotoUpload(photo: checkinPhoto, catchID: nil),
            PhotoUpload(photo: catchPhoto, catchID: withPhoto.id),
        ])
    }

    @Test func checkinPhotoLimit() {
        var draft = CheckinDraft(placeID: UUID(), photos: (0..<CheckinDraft.photoLimit).map { _ in photo() })
        #expect(draft.isValid)
        draft.photos.append(photo())
        #expect(!draft.isValid)
    }
}
