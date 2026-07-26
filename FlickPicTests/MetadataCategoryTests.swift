import Foundation
import Testing
@testable import FlickPic

@MainActor
struct MetadataCategoryTests {
    @Test
    func metadataFacetsOverlapWithoutVision() {
        let gifScreenshot = asset(
            id: "gif-screenshot",
            screenshot: true,
            gif: true
        )
        let slowScreenRecording = asset(
            id: "recording",
            kind: .video,
            screenRecording: true,
            slowMotion: true
        )

        #expect(MetadataCategory.images.matches(gifScreenshot))
        #expect(MetadataCategory.gifs.matches(gifScreenshot))
        #expect(MetadataCategory.screenshots.matches(gifScreenshot))
        #expect(!MetadataCategory.videos.matches(gifScreenshot))
        #expect(MetadataCategory.videos.matches(slowScreenRecording))
        #expect(MetadataCategory.screenRecordings.matches(slowScreenRecording))
        #expect(MetadataCategory.slowMotion.matches(slowScreenRecording))
    }

    @Test
    func everySpecialFacetMatchesItsDescriptorFlag() {
        let assets: [(MetadataCategory, MediaAssetDescriptor)] = [
            (.livePhotos, asset(id: "live", livePhoto: true)),
            (.panoramas, asset(id: "pano", panorama: true)),
            (.portraits, asset(id: "portrait", portrait: true)),
            (
                .timeLapse,
                asset(id: "timelapse", kind: .video, timeLapse: true)
            )
        ]

        for (category, asset) in assets {
            #expect(category.matches(asset))
        }
    }

    private func asset(
        id: String,
        kind: MediaKind = .photo,
        screenshot: Bool = false,
        livePhoto: Bool = false,
        gif: Bool = false,
        screenRecording: Bool = false,
        panorama: Bool = false,
        portrait: Bool = false,
        slowMotion: Bool = false,
        timeLapse: Bool = false
    ) -> MediaAssetDescriptor {
        MediaAssetDescriptor(
            id: id,
            mediaKind: kind,
            creationDate: .now,
            modificationDate: .now,
            pixelWidth: 1_200,
            pixelHeight: 1_600,
            duration: kind == .video ? 12 : 0,
            isFavorite: false,
            isScreenshot: screenshot,
            isLivePhoto: livePhoto,
            isGIF: gif,
            isScreenRecording: screenRecording,
            isPanorama: panorama,
            isPortrait: portrait,
            isSlowMotion: slowMotion,
            isTimeLapse: timeLapse
        )
    }
}
