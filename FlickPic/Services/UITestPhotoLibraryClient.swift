#if DEBUG
@preconcurrency import AVFoundation
import Foundation
import ImageIO
@preconcurrency import Photos
import UIKit
import UniformTypeIdentifiers

@MainActor
final class UITestPhotoLibraryClient: PhotoLibraryClient {
    let authorizationState: AuthorizationState = .full

    private var fetchAssetsCallCount = 0
    private var assets: [MediaAssetDescriptor] = [
        MediaAssetDescriptor(
            id: "ui-photo-1",
            mediaKind: .photo,
            creationDate: Date(timeIntervalSince1970: 100),
            modificationDate: Date(timeIntervalSince1970: 100),
            pixelWidth: 1_200,
            pixelHeight: 1_600,
            duration: 0,
            isFavorite: false,
            isScreenshot: false,
            isLivePhoto: false,
            isGIF: true
        ),
        MediaAssetDescriptor(
            id: "ui-photo-2",
            mediaKind: .photo,
            creationDate: Date(timeIntervalSince1970: 200),
            modificationDate: Date(timeIntervalSince1970: 200),
            pixelWidth: 1_600,
            pixelHeight: 1_200,
            duration: 0,
            isFavorite: false,
            isScreenshot: true,
            isLivePhoto: false
        ),
        MediaAssetDescriptor(
            id: "ui-video-1",
            mediaKind: .video,
            creationDate: Date(timeIntervalSince1970: 300),
            modificationDate: Date(timeIntervalSince1970: 300),
            pixelWidth: 1_920,
            pixelHeight: 1_080,
            duration: 12,
            isFavorite: false,
            isScreenshot: false,
            isLivePhoto: false
        )
    ]

    func requestAuthorization() async -> AuthorizationState {
        authorizationState
    }

    func fetchAssets(
        configuration: ReviewConfiguration,
        reviewedIdentifiers: Set<String>,
        pendingIdentifiers: Set<String>
    ) async throws -> [MediaAssetDescriptor] {
        fetchAssetsCallCount += 1
        if ProcessInfo.processInfo.arguments.contains(
            "-ui-testing-delayed-dashboard-refresh"
        ), fetchAssetsCallCount >= 3 {
            try await Task.sleep(for: .seconds(1))
        }

        let dateRange = configuration.normalizedDateRange
        let excludesReviewed =
            configuration.scope == .unreviewed || !configuration.includeReviewed

        return assets
            .filter { asset in
                guard !pendingIdentifiers.contains(asset.id) else { return false }
                guard !excludesReviewed
                        || !reviewedIdentifiers.contains(asset.id) else {
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
                    return configuration.order == .oldestFirst
                        ? left < right
                        : left > right
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
        let byIdentifier = Dictionary(
            uniqueKeysWithValues: assets.map { ($0.id, $0) }
        )
        return identifiers.compactMap { byIdentifier[$0] }
    }

    func thumbnail(
        identifier: String,
        targetSize: CGSize
    ) async throws -> UIImage {
        try fixtureImage(identifier: identifier, targetSize: targetSize)
    }

    func inspectionImage(
        identifier: String,
        targetSize: CGSize
    ) async throws -> UIImage {
        try fixtureImage(identifier: identifier, targetSize: targetSize)
    }

    func gifData(identifier: String) async throws -> Data? {
        identifier == "ui-photo-1" ? Self.fixtureGIFData : nil
    }

    func livePhoto(
        identifier: String,
        targetSize: CGSize
    ) async throws -> PHLivePhoto {
        throw PhotoLibraryError.imageUnavailable
    }

    func playerItem(identifier: String) async throws -> AVPlayerItem {
        guard assets.contains(where: { $0.id == identifier }) else {
            throw PhotoLibraryError.assetUnavailable
        }
        return AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
    }

    func recognitionImageData(identifier: String) async throws -> Data {
        let image = try fixtureImage(
            identifier: identifier,
            targetSize: CGSize(width: 640, height: 640)
        )
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw PhotoLibraryError.imageUnavailable
        }
        return data
    }

    func classificationImageData(
        identifier: String,
        allowNetworkAccess: Bool
    ) async throws -> Data {
        guard assets.contains(where: { $0.id == identifier }) else {
            throw PhotoLibraryError.assetUnavailable
        }
        return Data(identifier.utf8)
    }

    func exportCurrentMedia(identifier: String) async throws -> PreparedMediaExport {
        guard assets.contains(where: { $0.id == identifier }) else {
            throw PhotoLibraryError.assetUnavailable
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "FlickPicUITest-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fileExtension = identifier == "ui-photo-1" ? "gif" : "jpg"
        let file = directory.appendingPathComponent(
            "\(identifier).\(fileExtension)"
        )
        let data = identifier == "ui-photo-1"
            ? Self.fixtureGIFData ?? Data()
            : Data("FlickPic UI fixture".utf8)
        try data.write(to: file)
        return PreparedMediaExport(
            directoryURL: directory,
            itemURLs: [file]
        )
    }

    func discardExport(_ export: PreparedMediaExport) {
        try? FileManager.default.removeItem(at: export.directoryURL)
    }

    func deleteAssets(identifiers: [String]) async throws -> Set<String> {
        let requested = Set(identifiers)
        let resolved = Set(
            assets.map(\.id).filter(requested.contains)
        )
        assets.removeAll { resolved.contains($0.id) }
        return resolved
    }

    func preheat(identifiers: [String], targetSize: CGSize) {}

    func stopPreheating() {}

    private func fixtureImage(
        identifier: String,
        targetSize: CGSize
    ) throws -> UIImage {
        guard assets.contains(where: { $0.id == identifier }) else {
            throw PhotoLibraryError.assetUnavailable
        }
        let size = CGSize(
            width: min(max(targetSize.width, 64), 1_200),
            height: min(max(targetSize.height, 64), 1_600)
        )
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let text = identifier as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(
                    ofSize: max(min(size.width / 12, 54), 14),
                    weight: .semibold
                ),
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2
                ),
                withAttributes: attributes
            )
        }
    }

    private static let fixtureGIFData: Data? = {
        let size = CGSize(width: 160, height: 200)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.gif.identifier as CFString,
            2,
            nil
        ) else {
            return nil
        }

        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ] as [CFString: Any]
        ]
        CGImageDestinationSetProperties(
            destination,
            fileProperties as CFDictionary
        )

        for color in [UIColor.systemIndigo, UIColor.systemPink] {
            let image = UIGraphicsImageRenderer(size: size).image { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            guard let cgImage = image.cgImage else { return nil }
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: 0.2,
                    kCGImagePropertyGIFUnclampedDelayTime: 0.2
                ] as [CFString: Any]
            ]
            CGImageDestinationAddImage(
                destination,
                cgImage,
                frameProperties as CFDictionary
            )
        }

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }()
}

struct UITestImageClassificationClient: ImageClassificationClient {
    let classifierVersion = ImageClassificationPolicy.classifierVersion

    func classify(imageData: Data) async throws -> ImageClassificationResult {
        let identifier = String(decoding: imageData, as: UTF8.self)
        try await Task.sleep(
            for: identifier == "ui-photo-1"
                ? .milliseconds(150)
                : .seconds(6)
        )
        let tags: [VisionTag] = switch identifier {
        case "ui-photo-1":
            [VisionTag(identifier: "dog", confidence: 0.97)]
        case "ui-photo-2":
            [
                VisionTag(identifier: "dog", confidence: 0.95),
                VisionTag(identifier: "document", confidence: 0.92)
            ]
        default:
            []
        }
        return ImageClassificationResult(
            tags: tags,
            classifierVersion: classifierVersion
        )
    }
}
#endif
