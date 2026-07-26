import Foundation
import Observation

struct ClassificationScanOutcome: Equatable, Sendable {
    let wasCanceled: Bool
    let wasPausedBySystem: Bool
    let failedCount: Int
    let errorMessage: String?

    init(
        wasCanceled: Bool,
        wasPausedBySystem: Bool,
        failedCount: Int,
        errorMessage: String? = nil
    ) {
        self.wasCanceled = wasCanceled
        self.wasPausedBySystem = wasPausedBySystem
        self.failedCount = failedCount
        self.errorMessage = errorMessage
    }
}

@Observable
@MainActor
final class ClassificationCoordinator {
    private enum Attempt: Sendable {
        case classified(MediaAssetDescriptor, ImageClassificationResult)
        case deferredCloud(MediaAssetDescriptor)
        case failed(MediaAssetDescriptor)
        case canceled
    }

    private let classifier: any ImageClassificationClient
    private var workTask: Task<ClassificationScanOutcome, Never>?
    private var workID: UUID?
    private var currentRepository: ReviewRepository?
    private weak var currentPhotoLibrary: (any PhotoLibraryClient)?
    private var automaticRescanRequested = false
    private var isSuspendedForPhotoLibraryChange = false
    private var lowPowerObserver: NSObjectProtocol?
    private var thermalObserver: NSObjectProtocol?
    private var updateContinuations:
        [UUID: AsyncStream<ClassificationIndexUpdate>.Continuation] = [:]

    private(set) var isIndexing = false
    private(set) var completedCount = 0
    private(set) var totalCount = 0
    private(set) var failedCount = 0
    private(set) var deferredCloudCount = 0
    private(set) var lastCompletedAt: Date?
    private(set) var lastErrorMessage: String?
    private(set) var isReviewActive = false

    var classifierVersion: Int {
        classifier.classifierVersion
    }

    var fractionCompleted: Double {
        guard totalCount > 0 else { return isIndexing ? 0 : 1 }
        return min(Double(completedCount) / Double(totalCount), 1)
    }

    var statusDescription: String {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return "Paused by Low Power Mode"
        }
        if isThermallyConstrained {
            return "Paused while iPhone cools down"
        }
        if isIndexing {
            return isReviewActive
                ? "Categorizing while you review"
                : "Categorizing on device"
        }
        if lastErrorMessage != nil {
            return "Needs attention"
        }
        if deferredCloudCount > 0 {
            return "Waiting for iCloud"
        }
        if failedCount > 0 {
            return "\(failedCount) items need another attempt"
        }
        if lastCompletedAt != nil {
            return "Up to date"
        }
        return "Not started"
    }

    init(classifier: any ImageClassificationClient = VisionImageClassificationService()) {
        self.classifier = classifier

        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.systemConditionsDidChange()
            }
        }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.systemConditionsDidChange()
            }
        }
    }

    func updates() -> AsyncStream<ClassificationIndexUpdate> {
        let identifier = UUID()
        return AsyncStream { [weak self] continuation in
            self?.updateContinuations[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.updateContinuations.removeValue(forKey: identifier)
                }
            }
        }
    }

    func startAutomaticIndexing(
        repository: ReviewRepository,
        photoLibrary: any PhotoLibraryClient
    ) {
        currentRepository = repository
        currentPhotoLibrary = photoLibrary

        guard !isSuspendedForPhotoLibraryChange,
              photoLibrary.authorizationState.canReadLibrary,
              !isSystemConstrained else {
            return
        }
        guard workTask == nil else {
            automaticRescanRequested = true
            return
        }

        automaticRescanRequested = false
        let workID = UUID()
        self.workID = workID
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return ClassificationScanOutcome(
                    wasCanceled: true,
                    wasPausedBySystem: false,
                    failedCount: 0
                )
            }

            return await runLocalIndexing(
                repository: repository,
                photoLibrary: photoLibrary
            )
        }
        workTask = task

        Task { @MainActor [weak self] in
            let outcome = await task.value
            guard let self, self.workID == workID else { return }
            self.workTask = nil
            self.workID = nil
            if !outcome.wasCanceled {
                self.restartQueuedAutomaticIndexing()
            }
        }
    }

    func runLocalIndexing(
        repository: ReviewRepository,
        photoLibrary: any PhotoLibraryClient
    ) async -> ClassificationScanOutcome {
        guard photoLibrary.authorizationState.canReadLibrary,
              !isSystemConstrained else {
            return ClassificationScanOutcome(
                wasCanceled: false,
                wasPausedBySystem: true,
                failedCount: failedCount
            )
        }

        do {
            let assets = try await photoLibrary.classifiableAssets()
            return await runIndex(
                assets: assets,
                repository: repository,
                photoLibrary: photoLibrary,
                allowNetworkAccess: false,
                reconcileEntireLibrary: true
            )
        } catch is CancellationError {
            return canceledOutcome
        } catch {
            let message = error.localizedDescription
            lastErrorMessage = message
            return ClassificationScanOutcome(
                wasCanceled: false,
                wasPausedBySystem: false,
                failedCount: failedCount,
                errorMessage: message
            )
        }
    }

    func runBackgroundIndexing(
        repository: ReviewRepository,
        photoLibrary: any PhotoLibraryClient
    ) async -> Bool {
        guard photoLibrary.authorizationState.canReadLibrary else { return true }
        await stopCurrentWork()

        do {
            let assets = try await photoLibrary.classifiableAssets()
            let outcome = await runIndex(
                assets: assets,
                repository: repository,
                photoLibrary: photoLibrary,
                allowNetworkAccess: true,
                reconcileEntireLibrary: true
            )
            return !outcome.wasCanceled
                && !outcome.wasPausedBySystem
                && outcome.errorMessage == nil
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func cancelCurrentWork() {
        workTask?.cancel()
        isIndexing = false
    }

    func suspendForPhotoLibraryChange() async {
        guard !isSuspendedForPhotoLibraryChange else { return }
        isSuspendedForPhotoLibraryChange = true
        automaticRescanRequested = false
        await stopCurrentWork()
    }

    func resumeAfterPhotoLibraryChange() {
        guard isSuspendedForPhotoLibraryChange else { return }
        isSuspendedForPhotoLibraryChange = false
        restartAutomaticIndexingIfPossible()
    }

    func setReviewActive(_ active: Bool) {
        isReviewActive = active
        if !active, workTask == nil {
            restartAutomaticIndexingIfPossible()
        }
    }

    func retryFailed(
        repository: ReviewRepository,
        identifiers: Set<String>? = nil
    ) throws {
        try repository.retryFailedClassifications(identifiers: identifiers)
        failedCount = 0
        restartAutomaticIndexingIfPossible()
    }

    func rebuild(repository: ReviewRepository) async throws {
        await stopCurrentWork()
        try repository.rebuildClassificationIndex()
        completedCount = 0
        totalCount = 0
        failedCount = 0
        deferredCloudCount = 0
        lastCompletedAt = nil
        lastErrorMessage = nil
        publish(.reset)
        restartAutomaticIndexingIfPossible()
    }

    private func runIndex(
        assets: [MediaAssetDescriptor],
        repository: ReviewRepository,
        photoLibrary: any PhotoLibraryClient,
        allowNetworkAccess: Bool,
        reconcileEntireLibrary: Bool
    ) async -> ClassificationScanOutcome {
        guard !Task.isCancelled else {
            return canceledOutcome
        }

        isIndexing = true
        completedCount = 0
        totalCount = assets.count
        failedCount = 0
        deferredCloudCount = 0
        lastErrorMessage = nil

        var scanErrorMessage: String?
        do {
            var snapshots = try repository.classificationSnapshots()
            let availableIdentifiers = Set(assets.map(\.id))
            if reconcileEntireLibrary {
                let missing = Set(snapshots.keys).subtracting(availableIdentifiers)
                if !missing.isEmpty {
                    try repository.removeClassificationRecords(for: missing)
                    for identifier in missing {
                        snapshots.removeValue(forKey: identifier)
                    }
                    publish(.reset)
                }
            }

            var queuedAssets: [MediaAssetDescriptor] = []
            queuedAssets.reserveCapacity(min(assets.count, 1_000))

            for asset in assets {
                guard !Task.isCancelled else {
                    isIndexing = false
                    return canceledOutcome
                }

                if let snapshot = snapshots[asset.id],
                   snapshot.isCurrent(
                    for: asset,
                    classifierVersion: classifier.classifierVersion
                   ) {
                    switch snapshot.status {
                    case .classified:
                        completedCount += 1
                        continue
                    case .failed:
                        completedCount += 1
                        failedCount += 1
                        continue
                    case .deferredCloud where !allowNetworkAccess:
                        completedCount += 1
                        deferredCloudCount += 1
                        continue
                    case .deferredCloud:
                        break
                    }
                } else if let update = try repository.clearVisionTags(
                    identifier: asset.id
                ) {
                    publish(update)
                }
                queuedAssets.append(asset)
            }

            var index = 0
            while index < queuedAssets.count {
                guard !Task.isCancelled else {
                    isIndexing = false
                    return canceledOutcome
                }

                if isSystemConstrained {
                    isIndexing = false
                    return ClassificationScanOutcome(
                        wasCanceled: false,
                        wasPausedBySystem: true,
                        failedCount: failedCount
                    )
                }

                let batchSize = isReviewActive ? 1 : 2
                if batchSize == 2, index + 1 < queuedAssets.count {
                    let firstAsset = queuedAssets[index]
                    let secondAsset = queuedAssets[index + 1]
                    async let firstAttempt = attemptClassification(
                        asset: firstAsset,
                        photoLibrary: photoLibrary,
                        allowNetworkAccess: allowNetworkAccess
                    )
                    async let secondAttempt = attemptClassification(
                        asset: secondAsset,
                        photoLibrary: photoLibrary,
                        allowNetworkAccess: allowNetworkAccess
                    )
                    try persist(
                        attempt: await firstAttempt,
                        repository: repository
                    )
                    try persist(
                        attempt: await secondAttempt,
                        repository: repository
                    )
                    index += 2
                } else {
                    let attempt = await attemptClassification(
                        asset: queuedAssets[index],
                        photoLibrary: photoLibrary,
                        allowNetworkAccess: allowNetworkAccess
                    )
                    try persist(attempt: attempt, repository: repository)
                    index += 1
                }
            }
        } catch is CancellationError {
            isIndexing = false
            return canceledOutcome
        } catch {
            scanErrorMessage = error.localizedDescription
            lastErrorMessage = scanErrorMessage
        }

        isIndexing = false
        lastCompletedAt = .now
        if deferredCloudCount > 0 {
            ClassificationBackgroundScheduler.shared.schedule()
        }
        return ClassificationScanOutcome(
            wasCanceled: false,
            wasPausedBySystem: false,
            failedCount: failedCount,
            errorMessage: scanErrorMessage
        )
    }

    private func attemptClassification(
        asset: MediaAssetDescriptor,
        photoLibrary: any PhotoLibraryClient,
        allowNetworkAccess: Bool
    ) async -> Attempt {
        do {
            let imageData = try await photoLibrary.classificationImageData(
                identifier: asset.id,
                allowNetworkAccess: allowNetworkAccess
            )
            try Task.checkCancellation()
            let result = try await classifier.classify(imageData: imageData)
            try Task.checkCancellation()
            return .classified(asset, result)
        } catch ClassificationImageError.unavailableLocally {
            return .deferredCloud(asset)
        } catch is CancellationError {
            return .canceled
        } catch {
            return .failed(asset)
        }
    }

    private func persist(
        attempt: Attempt,
        repository: ReviewRepository
    ) throws {
        let update: ClassificationIndexUpdate
        switch attempt {
        case let .classified(asset, result):
            update = try repository.saveClassification(
                identifier: asset.id,
                tags: result.tags,
                modificationDate: asset.modificationDate,
                classifierVersion: result.classifierVersion,
                status: .classified
            )
        case let .deferredCloud(asset):
            update = try repository.saveClassification(
                identifier: asset.id,
                tags: [],
                modificationDate: asset.modificationDate,
                classifierVersion: classifier.classifierVersion,
                status: .deferredCloud
            )
            deferredCloudCount += 1
        case let .failed(asset):
            update = try repository.saveClassification(
                identifier: asset.id,
                tags: [],
                modificationDate: asset.modificationDate,
                classifierVersion: classifier.classifierVersion,
                status: .failed
            )
            failedCount += 1
        case .canceled:
            return
        }
        completedCount += 1
        publish(update)
    }

    private var canceledOutcome: ClassificationScanOutcome {
        let pausedBySystem = isSystemConstrained
        return ClassificationScanOutcome(
            wasCanceled: !pausedBySystem,
            wasPausedBySystem: pausedBySystem,
            failedCount: failedCount
        )
    }

    private var isSystemConstrained: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled || isThermallyConstrained
    }

    private var isThermallyConstrained: Bool {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            true
        case .nominal, .fair:
            false
        @unknown default:
            true
        }
    }

    private func publish(_ update: ClassificationIndexUpdate) {
        for continuation in updateContinuations.values {
            continuation.yield(update)
        }
    }

    private func systemConditionsDidChange() {
        if isSystemConstrained {
            cancelCurrentWork()
        } else {
            Task { @MainActor [weak self] in
                await self?.waitForCurrentWork()
                self?.restartAutomaticIndexingIfPossible()
            }
        }
    }

    private func restartAutomaticIndexingIfPossible() {
        guard let currentRepository, let currentPhotoLibrary else { return }
        startAutomaticIndexing(
            repository: currentRepository,
            photoLibrary: currentPhotoLibrary
        )
    }

    private func restartQueuedAutomaticIndexing() {
        guard automaticRescanRequested else { return }
        automaticRescanRequested = false
        restartAutomaticIndexingIfPossible()
    }

    private func stopCurrentWork() async {
        let priorTask = workTask
        let priorWorkID = workID
        priorTask?.cancel()
        if let priorTask {
            _ = await priorTask.value
        }
        if workID == priorWorkID {
            workTask = nil
            workID = nil
        }
        isIndexing = false
    }

    private func waitForCurrentWork() async {
        if let workTask {
            _ = await workTask.value
        }
    }
}
