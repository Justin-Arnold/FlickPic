enum MetadataCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case images
    case videos
    case gifs
    case livePhotos
    case screenshots
    case screenRecordings
    case panoramas
    case portraits
    case slowMotion
    case timeLapse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .images: "Images"
        case .videos: "Videos"
        case .gifs: "GIFs"
        case .livePhotos: "Live Photos"
        case .screenshots: "Screenshots"
        case .screenRecordings: "Screen Recordings"
        case .panoramas: "Panoramas"
        case .portraits: "Portraits"
        case .slowMotion: "Slow Motion"
        case .timeLapse: "Time-lapse"
        }
    }

    var systemImage: String {
        switch self {
        case .images: "photo"
        case .videos: "video"
        case .gifs: "sparkles.rectangle.stack"
        case .livePhotos: "livephoto"
        case .screenshots: "iphone"
        case .screenRecordings: "record.circle"
        case .panoramas: "pano"
        case .portraits: "person.crop.rectangle"
        case .slowMotion: "slowmo"
        case .timeLapse: "timelapse"
        }
    }

    func matches(_ asset: MediaAssetDescriptor) -> Bool {
        switch self {
        case .images: asset.mediaKind == .photo
        case .videos: asset.mediaKind == .video
        case .gifs: asset.isGIF
        case .livePhotos: asset.isLivePhoto
        case .screenshots: asset.isScreenshot
        case .screenRecordings: asset.isScreenRecording
        case .panoramas: asset.isPanorama
        case .portraits: asset.isPortrait
        case .slowMotion: asset.isSlowMotion
        case .timeLapse: asset.isTimeLapse
        }
    }
}
