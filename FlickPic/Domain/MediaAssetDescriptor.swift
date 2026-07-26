import Foundation
@preconcurrency import Photos

enum MediaKind: Int, Codable, CaseIterable, Identifiable, Sendable {
    case photo = 1
    case video = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .photo: "Photo"
        case .video: "Video"
        }
    }
}

struct MediaAssetDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let mediaKind: MediaKind
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let isFavorite: Bool
    let isScreenshot: Bool
    let isLivePhoto: Bool

    nonisolated init(
        id: String,
        mediaKind: MediaKind,
        creationDate: Date?,
        modificationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        duration: TimeInterval,
        isFavorite: Bool,
        isScreenshot: Bool,
        isLivePhoto: Bool
    ) {
        self.id = id
        self.mediaKind = mediaKind
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.isFavorite = isFavorite
        self.isScreenshot = isScreenshot
        self.isLivePhoto = isLivePhoto
    }

    nonisolated init?(asset: PHAsset) {
        guard let mediaKind = MediaKind(rawValue: asset.mediaType.rawValue) else {
            return nil
        }

        self.init(
            id: asset.localIdentifier,
            mediaKind: mediaKind,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            isFavorite: asset.isFavorite,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive)
        )
    }
}
