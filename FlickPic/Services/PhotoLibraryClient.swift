import AVFoundation
import Photos
import UIKit

struct PreparedMediaExport: Equatable, Sendable {
    let directoryURL: URL
    let itemURLs: [URL]
}

@MainActor
protocol PhotoLibraryClient: AnyObject, Sendable {
    var authorizationState: AuthorizationState { get }

    func requestAuthorization() async -> AuthorizationState
    func fetchAssets(
        configuration: ReviewConfiguration,
        reviewedIdentifiers: Set<String>,
        pendingIdentifiers: Set<String>
    ) async throws -> [MediaAssetDescriptor]
    func classifiableAssets() async throws -> [MediaAssetDescriptor]
    func descriptors(for identifiers: [String]) async -> [MediaAssetDescriptor]
    func thumbnail(
        identifier: String,
        targetSize: CGSize
    ) async throws -> UIImage
    func inspectionImage(
        identifier: String,
        targetSize: CGSize
    ) async throws -> UIImage
    func livePhoto(
        identifier: String,
        targetSize: CGSize
    ) async throws -> PHLivePhoto
    func playerItem(identifier: String) async throws -> AVPlayerItem
    func recognitionImageData(identifier: String) async throws -> Data
    func classificationImageData(
        identifier: String,
        allowNetworkAccess: Bool
    ) async throws -> Data
    func exportCurrentMedia(identifier: String) async throws -> PreparedMediaExport
    func discardExport(_ export: PreparedMediaExport)
    func deleteAssets(identifiers: [String]) async throws -> Set<String>
    func preheat(identifiers: [String], targetSize: CGSize)
    func stopPreheating()
}
