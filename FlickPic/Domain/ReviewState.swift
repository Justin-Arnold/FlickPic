import Foundation

enum PendingDeletionSource: String, Codable, CaseIterable, Sendable {
    case swipe
    case sharedCopy
    case extractedText
}

enum AuthorizationState: String, Sendable {
    case notDetermined
    case full
    case limited
    case denied
    case restricted

    var canReadLibrary: Bool {
        self == .full || self == .limited
    }
}

enum AssetReviewState: Equatable, Sendable {
    case unreviewed
    case kept(reviewedAt: Date)
    case pendingDeletion(source: PendingDeletionSource, queuedAt: Date)
}

enum PhotoLibraryError: LocalizedError {
    case assetUnavailable
    case imageUnavailable
    case gifUnavailable
    case exportResourceUnavailable
    case livePhotoExportUnsupported
    case noRecognizedText

    var errorDescription: String? {
        switch self {
        case .assetUnavailable: "This item is no longer available in the Photos library."
        case .imageUnavailable: "FlickPic could not load this item."
        case .gifUnavailable: "FlickPic could not load this animated GIF."
        case .exportResourceUnavailable: "FlickPic could not prepare a shareable copy."
        case .livePhotoExportUnsupported:
            "FlickPic cannot yet preserve a complete Live Photo when sharing a copy."
        case .noRecognizedText: "No readable text was found in this image."
        }
    }
}
