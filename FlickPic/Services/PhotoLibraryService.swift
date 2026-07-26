@preconcurrency import AVFoundation
import Observation
import OSLog
@preconcurrency import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@Observable
@MainActor
final class PhotoLibraryService: NSObject, PhotoLibraryClient {
    private static let deletionLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FlickPic",
        category: "PhotoDeletion"
    )

    private let imageManager = PHCachingImageManager()
    private let imageCache = NSCache<NSString, UIImage>()
    private let gifDataCache = NSCache<NSString, NSData>()
    private let catalog = PhotoKitCatalog()
    private let overrideClient: (any PhotoLibraryClient)?
    private let usesUITestAuthorizationOverride: Bool
    private var cachedAssets: [PHAsset] = []
    private var nonGIFIdentifiers: Set<String> = []
    private var isObservingLibrary = false

    private(set) var authorizationState: AuthorizationState
    private(set) var changeVersion = 0

    override init() {
        #if DEBUG
        let overrideClient: (any PhotoLibraryClient)? =
            ProcessInfo.processInfo.arguments.contains("-ui-testing-fixtures")
                ? UITestPhotoLibraryClient()
                : nil
        #else
        let overrideClient: (any PhotoLibraryClient)? = nil
        #endif
        let usesUITestAuthorizationOverride = overrideClient != nil
            || ProcessInfo.processInfo.arguments.contains("-ui-testing-authorized")
        self.overrideClient = overrideClient
        self.usesUITestAuthorizationOverride = usesUITestAuthorizationOverride
        authorizationState = overrideClient?.authorizationState
            ?? (usesUITestAuthorizationOverride
            ? .full
            : Self.authorizationState(
                from: PHPhotoLibrary.authorizationStatus(for: .readWrite)
            ))
        super.init()
        gifDataCache.totalCostLimit = 64 * 1_024 * 1_024
        cleanTemporaryExports()
        if authorizationState.canReadLibrary && !usesUITestAuthorizationOverride {
            beginObservingLibraryIfNeeded()
        }
    }

    func refreshAuthorizationState() {
        if let overrideClient {
            authorizationState = overrideClient.authorizationState
            return
        }
        guard !usesUITestAuthorizationOverride else {
            authorizationState = .full
            return
        }
        authorizationState = Self.authorizationState(
            from: PHPhotoLibrary.authorizationStatus(for: .readWrite)
        )
        if authorizationState.canReadLibrary {
            beginObservingLibraryIfNeeded()
        }
    }

    func requestAuthorization() async -> AuthorizationState {
        if let overrideClient {
            let state = await overrideClient.requestAuthorization()
            authorizationState = state
            return state
        }
        guard !usesUITestAuthorizationOverride else { return .full }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        let state = Self.authorizationState(from: status)
        authorizationState = state
        if state.canReadLibrary {
            beginObservingLibraryIfNeeded()
        }
        return state
    }

    func fetchAssets(
        configuration: ReviewConfiguration,
        reviewedIdentifiers: Set<String>,
        pendingIdentifiers: Set<String>
    ) async throws -> [MediaAssetDescriptor] {
        if let overrideClient {
            return try await overrideClient.fetchAssets(
                configuration: configuration,
                reviewedIdentifiers: reviewedIdentifiers,
                pendingIdentifiers: pendingIdentifiers
            )
        }
        return try await catalog.fetchAssets(
            configuration: configuration,
            reviewedIdentifiers: reviewedIdentifiers,
            pendingIdentifiers: pendingIdentifiers
        )
    }

    func classifiableAssets() async throws -> [MediaAssetDescriptor] {
        if let overrideClient {
            return try await overrideClient.classifiableAssets()
        }
        return try await catalog.classifiableAssets()
    }

    func descriptors(for identifiers: [String]) async -> [MediaAssetDescriptor] {
        if let overrideClient {
            return await overrideClient.descriptors(for: identifiers)
        }
        return await catalog.descriptors(for: identifiers)
    }

    func thumbnail(
        identifier: String,
        targetSize: CGSize
    ) async throws -> UIImage {
        if let overrideClient {
            return try await overrideClient.thumbnail(
                identifier: identifier,
                targetSize: targetSize
            )
        }
        let cacheKey = "\(identifier)-\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let asset = try asset(identifier: identifier)
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let cancellation = PhotoRequestCancellation()
        let image: UIImage = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    guard cancellation.claimCompletion() else { return }
                    if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(
                            throwing: Self.userFacingAssetLoadError(error)
                        )
                    } else if (info?[PHImageCancelledKey] as? Bool) == true {
                        continuation.resume(throwing: CancellationError())
                    } else if let image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(
                            throwing: PhotoLibraryError.imageUnavailable
                        )
                    }
                }
                cancellation.set(requestID)
                if Task.isCancelled {
                    imageManager.cancelImageRequest(requestID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if let requestID = cancellation.requestID {
                    self?.imageManager.cancelImageRequest(requestID)
                }
            }
        }

        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    func inspectionImage(
        identifier: String,
        targetSize: CGSize
    ) async throws -> UIImage {
        if let overrideClient {
            return try await overrideClient.inspectionImage(
                identifier: identifier,
                targetSize: targetSize
            )
        }
        let asset = try asset(identifier: identifier)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let cancellation = PhotoRequestCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    if (info?[PHImageResultIsDegradedKey] as? Bool) == true {
                        return
                    }
                    guard cancellation.claimCompletion() else { return }

                    if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: error)
                    } else if (info?[PHImageCancelledKey] as? Bool) == true {
                        continuation.resume(throwing: CancellationError())
                    } else if let image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: PhotoLibraryError.imageUnavailable)
                    }
                }
                cancellation.set(requestID)
                if Task.isCancelled {
                    imageManager.cancelImageRequest(requestID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if let requestID = cancellation.requestID {
                    self?.imageManager.cancelImageRequest(requestID)
                }
            }
        }
    }

    func gifData(identifier: String) async throws -> Data? {
        if let overrideClient {
            return try await overrideClient.gifData(identifier: identifier)
        }

        let cacheKey = identifier as NSString
        if let cached = gifDataCache.object(forKey: cacheKey) {
            return cached as Data
        }
        guard !nonGIFIdentifiers.contains(identifier) else { return nil }

        let asset = try asset(identifier: identifier)
        guard asset.mediaType == .image,
              asset.playbackStyle == .imageAnimated else {
            nonGIFIdentifiers.insert(identifier)
            return nil
        }

        let options = PHImageRequestOptions()
        options.version = .original
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        let cancellation = PhotoRequestCancellation()
        let data: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestID = imageManager.requestImageDataAndOrientation(
                    for: asset,
                    options: options
                ) { data, typeIdentifier, _, info in
                    guard cancellation.claimCompletion() else { return }

                    if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: error)
                    } else if (info?[PHImageCancelledKey] as? Bool) == true {
                        continuation.resume(throwing: CancellationError())
                    } else if let data {
                        if let typeIdentifier,
                           UTType(typeIdentifier)?.conforms(to: .gif) != true {
                            continuation.resume(
                                throwing: PhotoLibraryError.gifUnavailable
                            )
                        } else {
                            continuation.resume(returning: data)
                        }
                    } else {
                        continuation.resume(
                            throwing: PhotoLibraryError.gifUnavailable
                        )
                    }
                }
                cancellation.set(requestID)
                if Task.isCancelled {
                    imageManager.cancelImageRequest(requestID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if let requestID = cancellation.requestID {
                    self?.imageManager.cancelImageRequest(requestID)
                }
            }
        }

        gifDataCache.setObject(
            data as NSData,
            forKey: cacheKey,
            cost: data.count
        )
        return data
    }

    func livePhoto(
        identifier: String,
        targetSize: CGSize
    ) async throws -> PHLivePhoto {
        if let overrideClient {
            return try await overrideClient.livePhoto(
                identifier: identifier,
                targetSize: targetSize
            )
        }
        let asset = try asset(identifier: identifier)
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            imageManager.requestLivePhoto(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { livePhoto, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if (info?[PHImageCancelledKey] as? Bool) == true {
                    continuation.resume(throwing: CancellationError())
                } else if let livePhoto {
                    continuation.resume(returning: livePhoto)
                } else {
                    continuation.resume(throwing: PhotoLibraryError.imageUnavailable)
                }
            }
        }
    }

    func playerItem(identifier: String) async throws -> AVPlayerItem {
        if let overrideClient {
            return try await overrideClient.playerItem(identifier: identifier)
        }
        let asset = try asset(identifier: identifier)
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        let cancellation = PhotoRequestCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestID = imageManager.requestPlayerItem(
                    forVideo: asset,
                    options: options
                ) { item, info in
                    guard cancellation.claimCompletion() else { return }
                    if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(
                            throwing: Self.userFacingAssetLoadError(error)
                        )
                    } else if (info?[PHImageCancelledKey] as? Bool) == true {
                        continuation.resume(throwing: CancellationError())
                    } else if let item {
                        continuation.resume(returning: item)
                    } else {
                        continuation.resume(
                            throwing: PhotoLibraryError.imageUnavailable
                        )
                    }
                }
                cancellation.set(requestID)
                if Task.isCancelled {
                    imageManager.cancelImageRequest(requestID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if let requestID = cancellation.requestID {
                    self?.imageManager.cancelImageRequest(requestID)
                }
            }
        }
    }

    func recognitionImageData(identifier: String) async throws -> Data {
        if let overrideClient {
            return try await overrideClient.recognitionImageData(
                identifier: identifier
            )
        }
        let maxDimension: CGFloat = 2_400
        let image = try await thumbnail(
            identifier: identifier,
            targetSize: CGSize(width: maxDimension, height: maxDimension)
        )
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            throw PhotoLibraryError.imageUnavailable
        }
        return data
    }

    func classificationImageData(
        identifier: String,
        allowNetworkAccess: Bool
    ) async throws -> Data {
        if let overrideClient {
            return try await overrideClient.classificationImageData(
                identifier: identifier,
                allowNetworkAccess: allowNetworkAccess
            )
        }
        let asset = try asset(identifier: identifier)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowNetworkAccess

        let cancellation = PhotoRequestCancellation()
        let image: UIImage = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: CGSize(width: 640, height: 640),
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    guard cancellation.claimCompletion() else { return }
                    if !allowNetworkAccess,
                       (info?[PHImageResultIsInCloudKey] as? Bool) == true {
                        continuation.resume(
                            throwing: ClassificationImageError.unavailableLocally
                        )
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: error)
                    } else if (info?[PHImageCancelledKey] as? Bool) == true {
                        continuation.resume(throwing: CancellationError())
                    } else if let image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(
                            throwing: ClassificationImageError.unavailable
                        )
                    }
                }
                cancellation.set(requestID)
                if Task.isCancelled {
                    imageManager.cancelImageRequest(requestID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if let requestID = cancellation.requestID {
                    self?.imageManager.cancelImageRequest(requestID)
                }
            }
        }

        guard let data = image.jpegData(compressionQuality: 0.82) else {
            throw ClassificationImageError.unavailable
        }
        return data
    }

    func exportCurrentMedia(identifier: String) async throws -> PreparedMediaExport {
        if let overrideClient {
            return try await overrideClient.exportCurrentMedia(
                identifier: identifier
            )
        }
        let asset = try asset(identifier: identifier)
        guard !asset.mediaSubtypes.contains(.photoLive) else {
            throw PhotoLibraryError.livePhotoExportUnsupported
        }
        let resources = PHAssetResource.assetResources(for: asset)

        let preferredTypes: [PHAssetResourceType] = asset.mediaType == .video
            ? [.fullSizeVideo, .video]
            : [.fullSizePhoto, .photo]

        guard let resource = preferredTypes.lazy.compactMap({ type in
            resources.first(where: { $0.type == type })
        }).first else {
            throw PhotoLibraryError.exportResourceUnavailable
        }

        let exportDirectory = Self.exportDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )

        let originalName = resource.originalFilename.isEmpty
            ? "FlickPic-\(UUID().uuidString)"
            : resource.originalFilename
        let destination = exportDirectory
            .appendingPathComponent(UUID().uuidString + "-" + originalName)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        do {
            try await PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: destination,
                options: options
            )
            try Task.checkCancellation()
            return PreparedMediaExport(
                directoryURL: exportDirectory,
                itemURLs: [destination]
            )
        } catch {
            try? FileManager.default.removeItem(at: exportDirectory)
            throw error
        }
    }

    func discardExport(_ export: PreparedMediaExport) {
        if let overrideClient {
            overrideClient.discardExport(export)
            return
        }
        try? FileManager.default.removeItem(at: export.directoryURL)
    }

    func deleteAssets(identifiers: [String]) async throws -> Set<String> {
        guard !identifiers.isEmpty else { return [] }
        try await waitForAppAlertToDismiss()

        if let overrideClient {
            return try await overrideClient.deleteAssets(
                identifiers: identifiers
            )
        }

        let request = PhotoDeletionRequest(identifiers: identifiers)
        guard !request.resolvedIdentifiers.isEmpty else { return [] }
        let deletedCount = request.resolvedIdentifiers.count
        let changeBlock: @Sendable () -> Void = request.performChange

        Self.deletionLogger.info(
            "Submitting PhotoKit deletion for \(deletedCount, privacy: .public) assets"
        )
        do {
            try await PHPhotoLibrary.shared().performChanges(changeBlock)
            Self.deletionLogger.info(
                "PhotoKit deletion succeeded for \(deletedCount, privacy: .public) assets"
            )
        } catch {
            let nsError = error as NSError
            Self.deletionLogger.error(
                """
                PhotoKit deletion failed for \(deletedCount, privacy: .public) assets: \
                \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)
                """
            )
            throw error
        }
        return request.resolvedIdentifiers
    }

    func preheat(identifiers: [String], targetSize: CGSize) {
        if let overrideClient {
            overrideClient.preheat(
                identifiers: identifiers,
                targetSize: targetSize
            )
            return
        }
        stopPreheating()
        guard !identifiers.isEmpty else { return }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        cachedAssets = assets

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        )
    }

    func stopPreheating() {
        if let overrideClient {
            overrideClient.stopPreheating()
            return
        }
        guard !cachedAssets.isEmpty else { return }
        imageManager.stopCachingImagesForAllAssets()
        cachedAssets.removeAll()
    }

    func presentLimitedLibraryPicker() {
        guard let viewController = Self.topViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: viewController)
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            self?.imageCache.removeAllObjects()
            self?.gifDataCache.removeAllObjects()
            self?.nonGIFIdentifiers.removeAll()
            self?.changeVersion += 1
        }
    }

    private func asset(identifier: String) throws -> PHAsset {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        ).firstObject else {
            throw PhotoLibraryError.assetUnavailable
        }
        return asset
    }

    nonisolated static func userFacingAssetLoadError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == PHPhotosErrorDomain,
              nsError.code
                == PHPhotosError.Code.networkAccessRequired.rawValue else {
            return error
        }
        return PhotoLibraryError.iCloudDownloadRequired
    }

    private func waitForAppAlertToDismiss() async throws {
        while Self.topViewController() is UIAlertController {
            try await Task.sleep(for: .milliseconds(25))
        }
        await Task.yield()
    }

    private func beginObservingLibraryIfNeeded() {
        guard !isObservingLibrary else { return }
        PHPhotoLibrary.shared().register(self)
        isObservingLibrary = true
    }

    private static func authorizationState(
        from status: PHAuthorizationStatus
    ) -> AuthorizationState {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .full
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    private func cleanTemporaryExports() {
        try? FileManager.default.removeItem(at: Self.exportDirectory)
    }

    private static var exportDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FlickPicExports", isDirectory: true)
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController

        var current = root
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }
}

extension PhotoLibraryService: PHPhotoLibraryChangeObserver {}

private final class PhotoRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequestID: PHImageRequestID?
    private var hasCompleted = false

    var requestID: PHImageRequestID? {
        lock.withLock { storedRequestID }
    }

    func set(_ requestID: PHImageRequestID) {
        lock.withLock {
            storedRequestID = requestID
        }
    }

    func claimCompletion() -> Bool {
        lock.withLock {
            guard !hasCompleted else { return false }
            hasCompleted = true
            return true
        }
    }
}

private nonisolated final class PhotoDeletionRequest: @unchecked Sendable {
    private let assets: [PHAsset]
    let resolvedIdentifiers: Set<String>

    init(identifiers: [String]) {
        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: identifiers,
            options: nil
        )
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        self.assets = assets
        self.resolvedIdentifiers = Set(assets.map(\.localIdentifier))
    }

    func performChange() {
        PHAssetChangeRequest.deleteAssets(assets as NSArray)
    }
}
