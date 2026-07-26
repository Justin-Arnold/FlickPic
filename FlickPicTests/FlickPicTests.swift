import Foundation
import SwiftData
import Testing
import UIKit
@testable import FlickPic

@MainActor
struct ReviewRepositoryTests {
    @Test
    func keepQueueUndoAndResetPreserveTheRightState() throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)

        try repository.markKept(
            identifier: "photo-1",
            reviewedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(
            try repository.state(for: "photo-1")
                == .kept(reviewedAt: Date(timeIntervalSince1970: 100))
        )

        try repository.queueDeletion(
            identifier: "photo-1",
            source: .sharedCopy,
            queuedAt: Date(timeIntervalSince1970: 200)
        )
        #expect(
            try repository.state(for: "photo-1")
                == .pendingDeletion(
                    source: .sharedCopy,
                    queuedAt: Date(timeIntervalSince1970: 200)
                )
        )
        #expect(try repository.reviewedIdentifiers().isEmpty)

        try repository.resetReviewHistory()
        #expect(try repository.pendingIdentifiers() == ["photo-1"])

        try repository.returnToUnreviewed(identifier: "photo-1")
        #expect(try repository.state(for: "photo-1") == .unreviewed)
    }

    @Test
    func configurationAndOnboardingPersistWithoutSessionHistory() throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        var configuration = ReviewConfiguration()
        configuration.scope = .recent
        configuration.recentDays = 30
        configuration.mediaFilter = .videos
        configuration.order = .newestFirst
        configuration.includeFavorites = true

        try repository.saveConfiguration(configuration)
        try repository.completeOnboarding()

        let preference = try repository.preference()
        #expect(preference.hasCompletedOnboarding)
        #expect(preference.configuration == configuration)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ReviewedAsset.self,
            PendingDeletion.self,
            AppPreference.self,
            AssetClassification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

@MainActor
struct PendingDeletionQueueTests {
    @Test
    func limitedAccessPreservesMissingRecordsAndDeletesOnlyAccessibleAssets() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let library = FakePhotoLibraryClient(
            assets: [
                .fixture(id: "accessible"),
                .fixture(id: "limited-out")
            ]
        )
        library.authorizationState = .limited
        library.inaccessibleIdentifiers = ["limited-out"]
        try repository.queueDeletion(identifier: "accessible", source: .swipe)
        try repository.queueDeletion(identifier: "limited-out", source: .swipe)

        let loaded = await library.descriptors(
            for: ["accessible", "limited-out"]
        )
        let identifiersToRemove = PendingQueueReconciliation.identifiersToRemove(
            pendingIdentifiers: try repository.pendingIdentifiers(),
            availableIdentifiers: Set(loaded.map(\.id)),
            authorizationState: library.authorizationState
        )
        #expect(identifiersToRemove.isEmpty)

        let deleted = try await library.deleteAssets(
            identifiers: ["accessible", "limited-out"]
        )
        try repository.removeRecords(for: deleted)

        #expect(deleted == ["accessible"])
        #expect(try repository.pendingIdentifiers() == ["limited-out"])
    }

    @Test
    func fullAccessReconcilesAssetsMissingFromTheLibrary() {
        let missing = PendingQueueReconciliation.identifiersToRemove(
            pendingIdentifiers: ["available", "deleted"],
            availableIdentifiers: ["available"],
            authorizationState: .full
        )

        #expect(missing == ["deleted"])
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ReviewedAsset.self,
            PendingDeletion.self,
            AppPreference.self,
            AssetClassification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

@MainActor
struct RescueSafetyTests {
    @Test
    func livePhotosDoNotOfferCopyRescueUntilTheirMotionCanBePreserved() {
        let livePhoto = MediaAssetDescriptor.fixture(
            id: "live",
            livePhoto: true
        )
        let stillPhoto = MediaAssetDescriptor.fixture(id: "still")
        let video = MediaAssetDescriptor.fixture(id: "video", kind: .video)

        #expect(!RescueCapabilities.canShareCopy(livePhoto))
        #expect(RescueCapabilities.canShareCopy(stillPhoto))
        #expect(RescueCapabilities.canShareCopy(video))
    }

    @Test
    func preparedExportsCanBeDiscardedIdempotently() async throws {
        let library = FakePhotoLibraryClient()
        let export = try await library.exportCurrentMedia(identifier: "photo")

        library.discardExport(export)
        library.discardExport(export)

        #expect(library.discardedExportDirectories == [export.directoryURL])
    }
}

@MainActor
struct ReviewSessionModelTests {
    @Test
    func decisionsPersistAndUndoRestoresTheDeck() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let older = MediaAssetDescriptor.fixture(
            id: "older",
            date: Date(timeIntervalSince1970: 100)
        )
        let newer = MediaAssetDescriptor.fixture(
            id: "newer",
            date: Date(timeIntervalSince1970: 200)
        )
        let library = FakePhotoLibraryClient(assets: [newer, older])
        let model = ReviewSessionModel(
            configuration: ReviewConfiguration(),
            repository: repository,
            photoLibrary: library,
            hapticsEnabled: false
        )

        await model.load()

        #expect(model.currentAsset?.id == "older")
        #expect(model.positionText == "1 of 2")

        model.keepCurrent()
        #expect(try repository.state(for: "older").isKept)
        #expect(model.currentAsset?.id == "newer")

        model.queueCurrentForDeletion()
        #expect(model.currentAsset == nil)
        #expect(model.pendingCount == 1)

        model.undoLastDecision()
        #expect(model.currentAsset?.id == "newer")
        #expect(try repository.state(for: "newer") == .unreviewed)
        #expect(model.pendingCount == 0)
    }

    @Test
    func aNewSessionReconstructsOnlyUnreviewedItems() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let assets = [
            MediaAssetDescriptor.fixture(id: "kept"),
            MediaAssetDescriptor.fixture(id: "pending"),
            MediaAssetDescriptor.fixture(id: "untouched")
        ]
        let library = FakePhotoLibraryClient(assets: assets)

        try repository.markKept(identifier: "kept")
        try repository.queueDeletion(identifier: "pending", source: .swipe)

        let model = ReviewSessionModel(
            configuration: ReviewConfiguration(),
            repository: repository,
            photoLibrary: library,
            hapticsEnabled: false
        )
        await model.load()

        #expect(model.assets.map(\.id) == ["untouched"])
        #expect(model.pendingCount == 1)
    }

    @Test
    func laterRotatesWithoutChangingPersistentState() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let library = FakePhotoLibraryClient(
            assets: [
                .fixture(id: "first", date: Date(timeIntervalSince1970: 1)),
                .fixture(id: "second", date: Date(timeIntervalSince1970: 2))
            ]
        )
        let model = ReviewSessionModel(
            configuration: ReviewConfiguration(),
            repository: repository,
            photoLibrary: library,
            hapticsEnabled: false
        )
        await model.load()

        model.moveCurrentToLater()

        #expect(model.assets.map { $0.id } == ["second", "first"])
        #expect(try repository.state(for: "first") == .unreviewed)
        #expect(model.positionText == "1 of 2")
    }

    @Test
    func largeLibraryCanBeFilteredWithoutCreatingSessionRecords() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let library = FakePhotoLibraryClient(
            assets: (0..<50_000).map {
                .fixture(
                    id: "asset-\($0)",
                    date: Date(timeIntervalSince1970: TimeInterval($0))
                )
            }
        )
        let model = ReviewSessionModel(
            configuration: ReviewConfiguration(),
            repository: repository,
            photoLibrary: library,
            hapticsEnabled: false
        )

        await model.load()

        #expect(model.assets.count == 50_000)
        #expect(try repository.reviewedIdentifiers().isEmpty)
        #expect(try repository.pendingIdentifiers().isEmpty)
    }

    @Test
    func staleAndEndedDecisionsCannotAdvanceAnotherAsset() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let library = FakePhotoLibraryClient(
            assets: [
                .fixture(id: "first", date: Date(timeIntervalSince1970: 1)),
                .fixture(id: "second", date: Date(timeIntervalSince1970: 2))
            ]
        )
        let model = ReviewSessionModel(
            configuration: ReviewConfiguration(),
            repository: repository,
            photoLibrary: library,
            hapticsEnabled: false
        )
        await model.load()

        #expect(model.keepCurrent(expectedIdentifier: "first"))
        #expect(model.currentAsset?.id == "second")
        #expect(
            !model.queueCurrentForDeletion(
                expectedIdentifier: "first"
            )
        )
        #expect(model.currentAsset?.id == "second")
        #expect(try repository.state(for: "second") == .unreviewed)

        model.endSession()
        #expect(!model.keepCurrent(expectedIdentifier: "second"))
        #expect(try repository.state(for: "second") == .unreviewed)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ReviewedAsset.self,
            PendingDeletion.self,
            AppPreference.self,
            AssetClassification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

@MainActor
struct ReviewConfigurationTests {
    @Test
    func customRangeNormalizesReversedDatesAndIncludesWholeDays() {
        let calendar = Calendar(identifier: .gregorian)
        let early = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 2, hour: 12)
        )!
        let late = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 5, hour: 8)
        )!

        var configuration = ReviewConfiguration()
        configuration.scope = .custom
        configuration.customStart = late
        configuration.customEnd = early

        let range = configuration.normalizedDateRange
        #expect(range?.contains(early) == true)
        #expect(range?.contains(late) == true)
        #expect(range.map { $0.lowerBound <= early } == true)
        #expect(range.map { $0.upperBound >= late } == true)
    }

    @Test
    func screenshotsAlwaysUseThePhotoFilter() {
        var configuration = ReviewConfiguration()
        configuration.category = .screenshots
        configuration.mediaFilter = .videos

        #expect(configuration.effectiveMediaFilter == .photos)
        #expect(configuration.summary.contains("Screenshots"))
        #expect(!configuration.summary.contains("Videos"))
    }
}

@MainActor
struct InspectionImageSizingTests {
    @Test
    func ordinaryPhotoKeepsItsAvailableResolution() {
        let asset = MediaAssetDescriptor.fixture(
            id: "ordinary",
            pixelWidth: 4_000,
            pixelHeight: 3_000
        )

        #expect(
            InspectionImageSizing.targetSize(for: asset)
                == CGSize(width: 4_000, height: 3_000)
        )
    }

    @Test
    func veryLongScreenshotPreservesAspectRatioWithinMemoryBounds() {
        let asset = MediaAssetDescriptor.fixture(
            id: "long-screenshot",
            pixelWidth: 1_080,
            pixelHeight: 30_000,
            screenshot: true
        )

        let target = InspectionImageSizing.targetSize(for: asset)
        let targetPixels = target.width * target.height
        let sourceAspectRatio = 1_080.0 / 30_000.0
        let targetAspectRatio = target.width / target.height

        #expect(target.width == 720)
        #expect(target.height == 20_000)
        #expect(targetPixels <= InspectionImageSizing.maximumPixelCount)
        #expect(abs(targetAspectRatio - sourceAspectRatio) < 0.0001)
    }

    @Test
    func rotatedCameraImageUsesItsDisplayedOrientationForZoomGeometry() {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 40, height: 20)
        )
        let upright = renderer.image { _ in }
        let rotated = UIImage(
            cgImage: upright.cgImage!,
            scale: upright.scale,
            orientation: .right
        )

        #expect(
            InspectionImageSizing.displaySize(for: rotated)
                == CGSize(width: 20, height: 40)
        )
    }
}

@MainActor
struct ImageClassificationPolicyTests {
    @Test
    func receiptWinsOverDocumentInTheExclusiveHierarchy() {
        let result = ImageClassificationPolicy.resolve(
            candidates: [
                ClassificationCandidate(
                    identifier: "document",
                    confidence: 0.99,
                    meetsHighPrecision: true
                ),
                ClassificationCandidate(
                    identifier: "receipt",
                    confidence: 0.91,
                    meetsHighPrecision: true
                )
            ],
            classifierVersion: 7
        )

        #expect(result.category == .receipt)
        #expect(result.confidence == 0.91)
        #expect(result.classifierVersion == 7)
    }

    @Test
    func documentRequiresHighPrecisionAndOtherwiseFallsBackToOtherPhoto() {
        let document = ImageClassificationPolicy.resolve(
            candidates: [
                ClassificationCandidate(
                    identifier: "receipt",
                    confidence: 0.95,
                    meetsHighPrecision: false
                ),
                ClassificationCandidate(
                    identifier: "document",
                    confidence: 0.92,
                    meetsHighPrecision: true
                )
            ],
            classifierVersion: 1
        )
        let other = ImageClassificationPolicy.resolve(
            candidates: [
                ClassificationCandidate(
                    identifier: "document",
                    confidence: 0.89,
                    meetsHighPrecision: false
                )
            ],
            classifierVersion: 1
        )

        #expect(document.category == .document)
        #expect(other.category == .otherPhoto)
    }
}

@MainActor
struct ClassificationPersistenceTests {
    @Test
    func legacyScreenshotScopeMigratesToTheCategoryDimension() throws {
        let container = try makeContainer()
        let preference = AppPreference()
        preference.scopeRawValue = ReviewScopeKind.screenshots.rawValue
        preference.mediaFilterRawValue = MediaFilter.videos.rawValue
        container.mainContext.insert(preference)
        try container.mainContext.save()

        let migrated = try ReviewRepository(modelContext: container.mainContext)
            .preference()

        #expect(migrated.scopeRawValue == ReviewScopeKind.unreviewed.rawValue)
        #expect(migrated.configuration.scope == .unreviewed)
        #expect(migrated.configuration.category == .screenshots)
        #expect(migrated.configuration.mediaFilter == .photos)
    }

    @Test
    func resetHistoryPreservesClassificationsButAssetRemovalDoesNot() throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        try repository.markKept(identifier: "receipt")
        try repository.saveClassification(
            identifier: "receipt",
            category: .receipt,
            confidence: 0.95,
            modificationDate: Date(timeIntervalSince1970: 100),
            classifierVersion: ImageClassificationPolicy.classifierVersion,
            status: .classified
        )

        try repository.resetReviewHistory()
        #expect(try repository.classificationSnapshots()["receipt"]?.category == .receipt)

        try repository.removeRecords(for: ["receipt"])
        #expect(try repository.classificationSnapshots()["receipt"] == nil)
    }

    @Test
    func cacheSnapshotInvalidatesForEditsAndClassifierChanges() {
        let originalDate = Date(timeIntervalSince1970: 100)
        let editedDate = Date(timeIntervalSince1970: 200)
        let asset = MediaAssetDescriptor.fixture(
            id: "asset",
            modificationDate: originalDate
        )
        let editedAsset = MediaAssetDescriptor.fixture(
            id: "asset",
            modificationDate: editedDate
        )
        let snapshot = ClassificationCacheSnapshot(
            assetIdentifier: "asset",
            category: .document,
            confidence: 0.9,
            assetModificationDate: originalDate,
            classifierVersion: 1,
            status: .classified,
            lastAttemptAt: .now
        )

        #expect(snapshot.isCurrent(for: asset, classifierVersion: 1))
        #expect(!snapshot.isCurrent(for: editedAsset, classifierVersion: 1))
        #expect(!snapshot.isCurrent(for: asset, classifierVersion: 2))
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ReviewedAsset.self,
            PendingDeletion.self,
            AppPreference.self,
            AssetClassification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

@MainActor
struct CategoryDeckTests {
    @Test
    func categoryFiltersRemainExclusive() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let screenshot = MediaAssetDescriptor.fixture(id: "screenshot", screenshot: true)
        let receipt = MediaAssetDescriptor.fixture(id: "receipt")
        let document = MediaAssetDescriptor.fixture(id: "document")
        let other = MediaAssetDescriptor.fixture(id: "other")
        let library = FakePhotoLibraryClient(
            assets: [screenshot, receipt, document, other]
        )

        try save(
            category: .screenshot,
            asset: screenshot,
            repository: repository
        )
        try save(category: .receipt, asset: receipt, repository: repository)
        try save(category: .document, asset: document, repository: repository)
        try save(category: .otherPhoto, asset: other, repository: repository)

        let expectations: [(ContentCategoryFilter, [String])] = [
            (.screenshots, ["screenshot"]),
            (.receipts, ["receipt"]),
            (.documents, ["document"]),
            (.otherPhotos, ["other"])
        ]

        for (category, identifiers) in expectations {
            var configuration = ReviewConfiguration()
            configuration.category = category
            let model = ReviewSessionModel(
                configuration: configuration,
                repository: repository,
                photoLibrary: library,
                hapticsEnabled: false
            )
            await model.load()
            #expect(model.assets.map(\.id) == identifiers)
        }
    }

    @Test
    func categoryCombinesWithDateFavoritesReviewedStateMediaAndOrder() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let now = Date.now
        let included = MediaAssetDescriptor.fixture(
            id: "included",
            date: now.addingTimeInterval(-3_600)
        )
        let favorite = MediaAssetDescriptor.fixture(
            id: "favorite",
            date: now.addingTimeInterval(-1_800),
            favorite: true
        )
        let reviewed = MediaAssetDescriptor.fixture(
            id: "reviewed",
            date: now.addingTimeInterval(-900)
        )
        let tooOld = MediaAssetDescriptor.fixture(
            id: "too-old",
            date: now.addingTimeInterval(-20 * 86_400)
        )
        let document = MediaAssetDescriptor.fixture(
            id: "document",
            date: now.addingTimeInterval(-600)
        )
        let video = MediaAssetDescriptor.fixture(
            id: "video",
            kind: .video,
            date: now.addingTimeInterval(-300)
        )
        let assets = [included, favorite, reviewed, tooOld, document, video]
        let library = FakePhotoLibraryClient(assets: assets)

        for asset in [included, favorite, reviewed, tooOld, video] {
            try save(category: .receipt, asset: asset, repository: repository)
        }
        try save(category: .document, asset: document, repository: repository)
        try repository.markKept(identifier: reviewed.id)

        var configuration = ReviewConfiguration()
        configuration.scope = .recent
        configuration.recentDays = 7
        configuration.category = .receipts
        configuration.mediaFilter = .videos
        configuration.order = .newestFirst

        let protectedModel = ReviewSessionModel(
            configuration: configuration,
            repository: repository,
            photoLibrary: library,
            hapticsEnabled: false
        )
        await protectedModel.load()
        #expect(protectedModel.assets.map(\.id) == ["included"])

        configuration.includeFavorites = true
        configuration.includeReviewed = true
        let inclusiveModel = ReviewSessionModel(
            configuration: configuration,
            repository: repository,
            photoLibrary: library,
            hapticsEnabled: false
        )
        await inclusiveModel.load()
        #expect(
            inclusiveModel.assets.map(\.id)
                == ["reviewed", "favorite", "included"]
        )
    }

    private func save(
        category: ContentCategory,
        asset: MediaAssetDescriptor,
        repository: ReviewRepository
    ) throws {
        try repository.saveClassification(
            identifier: asset.id,
            category: category,
            confidence: 1,
            modificationDate: asset.modificationDate,
            classifierVersion: ImageClassificationPolicy.classifierVersion,
            status: .classified
        )
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ReviewedAsset.self,
            PendingDeletion.self,
            AppPreference.self,
            AssetClassification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

@MainActor
struct ClassificationCoordinatorTests {
    @Test
    func screenshotBypassesVisionAndCloudAssetsRetryExplicitly() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let screenshot = MediaAssetDescriptor.fixture(id: "screenshot", screenshot: true)
        let receipt = MediaAssetDescriptor.fixture(id: "receipt")
        let cloudDocument = MediaAssetDescriptor.fixture(id: "cloud-document")
        let library = FakePhotoLibraryClient(
            assets: [screenshot, receipt, cloudDocument]
        )
        library.locallyUnavailableIdentifiers = ["cloud-document"]

        let probe = ClassificationProbe()
        let classifier = FakeImageClassificationClient(
            results: [
                "receipt": ImageClassificationResult(
                    category: .receipt,
                    confidence: 0.94,
                    classifierVersion: ImageClassificationPolicy.classifierVersion
                ),
                "cloud-document": ImageClassificationResult(
                    category: .document,
                    confidence: 0.93,
                    classifierVersion: ImageClassificationPolicy.classifierVersion
                )
            ],
            probe: probe
        )
        let coordinator = ClassificationCoordinator(classifier: classifier)

        _ = await coordinator.runLocalIndexing(
            repository: repository,
            photoLibrary: library
        )

        var snapshots = try repository.classificationSnapshots()
        #expect(snapshots["screenshot"]?.category == .screenshot)
        #expect(snapshots["receipt"]?.category == .receipt)
        #expect(snapshots["cloud-document"]?.status == .deferredCloud)
        let classifiedIdentifiers = await probe.identifiers
        #expect(!classifiedIdentifiers.contains("screenshot"))

        var configuration = ReviewConfiguration()
        configuration.category = .documents
        let outcome = await coordinator.prepareCategory(
            configuration: configuration,
            repository: repository,
            photoLibrary: library
        )

        snapshots = try repository.classificationSnapshots()
        #expect(!outcome.wasCanceled)
        #expect(snapshots["cloud-document"]?.category == .document)
        #expect(
            library.classificationRequests.contains {
                $0.identifier == "cloud-document" && $0.allowNetworkAccess
            }
        )
    }

    @Test
    func classificationConcurrencyNeverExceedsTwo() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let library = FakePhotoLibraryClient(
            assets: (0..<8).map {
                .fixture(id: "asset-\($0)", modificationDate: Date(timeIntervalSince1970: 1))
            }
        )
        let probe = ClassificationProbe()
        let coordinator = ClassificationCoordinator(
            classifier: FakeImageClassificationClient(
                delay: .milliseconds(10),
                probe: probe
            )
        )

        _ = await coordinator.runLocalIndexing(
            repository: repository,
            photoLibrary: library
        )

        let maximumConcurrentCalls = await probe.maximumConcurrentCalls
        #expect(maximumConcurrentCalls == 2)
        #expect(try repository.classificationSnapshots().count == 8)
    }

    @Test
    func failedItemsStayUnknownUntilExplicitlyRetried() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let asset = MediaAssetDescriptor.fixture(id: "broken")
        let library = FakePhotoLibraryClient(assets: [asset])
        let failingCoordinator = ClassificationCoordinator(
            classifier: FakeImageClassificationClient(
                failingIdentifiers: ["broken"]
            )
        )
        var configuration = ReviewConfiguration()
        configuration.category = .otherPhotos

        let failedOutcome = await failingCoordinator.prepareCategory(
            configuration: configuration,
            repository: repository,
            photoLibrary: library
        )

        #expect(failedOutcome.failedCount == 1)
        #expect(try repository.classificationSnapshots()["broken"]?.status == .failed)

        // The next scan uses a replacement classifier, so keep the intentionally
        // failing coordinator from auto-retrying against the same repository.
        failingCoordinator.setReviewActive(true)
        try failingCoordinator.retryFailed(repository: repository)
        let successfulCoordinator = ClassificationCoordinator(
            classifier: FakeImageClassificationClient()
        )
        let successOutcome = await successfulCoordinator.prepareCategory(
            configuration: configuration,
            repository: repository,
            photoLibrary: library
        )

        #expect(successOutcome.failedCount == 0)
        #expect(
            try repository.classificationSnapshots()["broken"]?.category
                == .otherPhoto
        )
    }

    @Test
    func cancellationKeepsCompletedResultsAndLeavesTheRestForResume() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let library = FakePhotoLibraryClient(
            assets: (0..<8).map { .fixture(id: "asset-\($0)") }
        )
        let coordinator = ClassificationCoordinator(
            classifier: FakeImageClassificationClient(delay: .milliseconds(30))
        )
        var configuration = ReviewConfiguration()
        configuration.category = .receipts

        let scan = Task { @MainActor in
            await coordinator.prepareCategory(
                configuration: configuration,
                repository: repository,
                photoLibrary: library
            )
        }

        for _ in 0..<100 {
            if try repository.classificationSnapshots().count >= 2 {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        coordinator.cancelCurrentWork()
        let outcome = await scan.value
        let savedCount = try repository.classificationSnapshots().count

        #expect(outcome.wasCanceled)
        #expect(savedCount >= 2)
        #expect(savedCount < library.assets.count)
    }

    @Test
    func modifiedAssetsAreReclassifiedInsteadOfUsingStaleCache() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        let modified = MediaAssetDescriptor.fixture(
            id: "modified",
            modificationDate: newDate
        )
        let library = FakePhotoLibraryClient(assets: [modified])
        try repository.saveClassification(
            identifier: modified.id,
            category: .document,
            confidence: 0.95,
            modificationDate: oldDate,
            classifierVersion: ImageClassificationPolicy.classifierVersion,
            status: .classified
        )
        let coordinator = ClassificationCoordinator(
            classifier: FakeImageClassificationClient(
                results: [
                    modified.id: ImageClassificationResult(
                        category: .receipt,
                        confidence: 0.96,
                        classifierVersion: ImageClassificationPolicy.classifierVersion
                    )
                ]
            )
        )

        _ = await coordinator.runLocalIndexing(
            repository: repository,
            photoLibrary: library
        )

        let snapshot = try repository.classificationSnapshots()[modified.id]
        #expect(snapshot?.category == .receipt)
        #expect(snapshot?.assetModificationDate == newDate)
        #expect(library.classificationRequests.map(\.identifier) == [modified.id])
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ReviewedAsset.self,
            PendingDeletion.self,
            AppPreference.self,
            AssetClassification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

private extension AssetReviewState {
    var isKept: Bool {
        if case .kept = self { return true }
        return false
    }
}
