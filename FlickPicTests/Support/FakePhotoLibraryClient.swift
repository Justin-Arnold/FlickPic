import AVFoundation
import Photos
import UIKit
@testable import FlickPic

@MainActor
final class FakePhotoLibraryClient: PhotoLibraryClient {
    var authorizationState: AuthorizationState = .full
    var assets: [MediaAssetDescriptor]
    var deletedIdentifiers: [String] = []
    var preheatedIdentifiers: [String] = []
    var inaccessibleIdentifiers: Set<String> = []
    var locallyUnavailableIdentifiers: Set<String> = []
    var classificationFailureIdentifiers: Set<String> = []
    var classificationRequests: [(identifier: String, allowNetworkAccess: Bool)] = []
    var inspectionRequests: [(identifier: String, targetSize: CGSize)] = []
    var gifDataByIdentifier: [String: Data] = [:]
    var gifDataRequests: [String] = []
    var playerItemRequests: [String] = []
    var playerItemError: Error?
    var playerItemHandler:
        ((String) async throws -> AVPlayerItem)?
    var discardedExportDirectories: Set<URL> = []
    var fetchAssetsDelay: Duration?

    init(assets: [MediaAssetDescriptor] = []) {
        self.assets = assets
    }

    func requestAuthorization() async -> AuthorizationState {
        authorizationState
    }

    func fetchAssets(
        configuration: ReviewConfiguration,
        reviewedIdentifiers: Set<String>,
        pendingIdentifiers: Set<String>
    ) async throws -> [MediaAssetDescriptor] {
        if let fetchAssetsDelay {
            try await Task.sleep(for: fetchAssetsDelay)
        }
        let dateRange = configuration.normalizedDateRange
        let excludesReviewed =
            configuration.scope == .unreviewed || !configuration.includeReviewed

        return assets
            .filter { asset in
                guard !pendingIdentifiers.contains(asset.id) else { return false }
                guard !excludesReviewed || !reviewedIdentifiers.contains(asset.id) else {
                    return false
                }
                guard configuration.includeFavorites || !asset.isFavorite else {
                    return false
                }

                switch configuration.effectiveMediaFilter {
                case .all:
                    break
                case .photos where asset.mediaKind != .photo:
                    return false
                case .videos where asset.mediaKind != .video:
                    return false
                default:
                    break
                }

                if let dateRange {
                    guard let creationDate = asset.creationDate,
                          dateRange.contains(creationDate) else {
                        return false
                    }
                }
                return true
            }
            .sorted { lhs, rhs in
                switch (lhs.creationDate, rhs.creationDate) {
                case let (left?, right?) where left != right:
                    return configuration.order == .oldestFirst ? left < right : left > right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.id < rhs.id
                }
            }
    }

    func classifiableAssets() async throws -> [MediaAssetDescriptor] {
        assets.filter { $0.mediaKind == .photo }
    }

    func descriptors(for identifiers: [String]) async -> [MediaAssetDescriptor] {
        let byIdentifier = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        return identifiers.compactMap {
            inaccessibleIdentifiers.contains($0) ? nil : byIdentifier[$0]
        }
    }

    func thumbnail(identifier: String, targetSize: CGSize) async throws -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
    }

    func inspectionImage(
        identifier: String,
        targetSize: CGSize
    ) async throws -> UIImage {
        inspectionRequests.append((identifier, targetSize))
        return UIGraphicsImageRenderer(size: targetSize).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
        }
    }

    func gifData(identifier: String) async throws -> Data? {
        gifDataRequests.append(identifier)
        return gifDataByIdentifier[identifier]
    }

    func livePhoto(identifier: String, targetSize: CGSize) async throws -> PHLivePhoto {
        throw PhotoLibraryError.imageUnavailable
    }

    func playerItem(identifier: String) async throws -> AVPlayerItem {
        playerItemRequests.append(identifier)
        if let playerItemHandler {
            return try await playerItemHandler(identifier)
        }
        if let playerItemError {
            throw playerItemError
        }
        return AVPlayerItem(
            url: URL(fileURLWithPath: "/dev/null")
        )
    }

    func recognitionImageData(identifier: String) async throws -> Data {
        Data()
    }

    func classificationImageData(
        identifier: String,
        allowNetworkAccess: Bool
    ) async throws -> Data {
        classificationRequests.append((identifier, allowNetworkAccess))
        if locallyUnavailableIdentifiers.contains(identifier), !allowNetworkAccess {
            throw ClassificationImageError.unavailableLocally
        }
        if classificationFailureIdentifiers.contains(identifier) {
            throw ClassificationImageError.unavailable
        }
        return Data(identifier.utf8)
    }

    func exportCurrentMedia(identifier: String) async throws -> PreparedMediaExport {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FakeExport-\(identifier)", isDirectory: true)
        return PreparedMediaExport(
            directoryURL: directory,
            itemURLs: [directory.appendingPathComponent(identifier)]
        )
    }

    func discardExport(_ export: PreparedMediaExport) {
        discardedExportDirectories.insert(export.directoryURL)
    }

    func deleteAssets(identifiers: [String]) async throws -> Set<String> {
        let requested = Set(identifiers)
        let resolved = Set(
            assets
                .map(\.id)
                .filter {
                    requested.contains($0)
                        && !inaccessibleIdentifiers.contains($0)
                }
        )
        deletedIdentifiers = identifiers.filter(resolved.contains)
        assets.removeAll { resolved.contains($0.id) }
        return resolved
    }

    func preheat(identifiers: [String], targetSize: CGSize) {
        preheatedIdentifiers = identifiers
    }

    func stopPreheating() {
        preheatedIdentifiers = []
    }
}

extension MediaAssetDescriptor {
    @MainActor
    static func fixture(
        id: String,
        kind: MediaKind = .photo,
        date: Date? = .now,
        modificationDate: Date? = .now,
        pixelWidth: Int = 1_200,
        pixelHeight: Int = 1_600,
        favorite: Bool = false,
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
            creationDate: date,
            modificationDate: modificationDate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            duration: kind == .video ? 12 : 0,
            isFavorite: favorite,
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
