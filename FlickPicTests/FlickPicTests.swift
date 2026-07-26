import Foundation
@preconcurrency import Photos
import SwiftData
import Testing
import UIKit
@testable import FlickPic

struct PhotoLibraryErrorTests {
    @Test
    func networkRequiredErrorsUseAnActionableICloudMessage() {
        let photoKitError = NSError(
            domain: PHPhotosErrorDomain,
            code: PHPhotosError.Code.networkAccessRequired.rawValue
        )

        let mapped = PhotoLibraryService.userFacingAssetLoadError(photoKitError)

        #expect(
            mapped.localizedDescription
                == "This item needs to download from iCloud. Check your connection and try again."
        )
    }
}

struct VisionCategoryDisplayPolicyTests {
    @Test
    func hidesScreenshotIdentifiersAlreadyCoveredByMetadata() {
        #expect(
            !VisionCategoryDisplayPolicy.shouldDisplay(
                identifier: "screenshot"
            )
        )
        #expect(
            !VisionCategoryDisplayPolicy.shouldDisplay(
                identifier: "Screenshots"
            )
        )
        #expect(
            !VisionCategoryDisplayPolicy.shouldDisplay(
                identifier: "screen_shot"
            )
        )
        #expect(
            VisionCategoryDisplayPolicy.shouldDisplay(
                identifier: "screen"
            )
        )
    }
}

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
            VisionTagAssignment.self,
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
            VisionTagAssignment.self,
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
            VisionTagAssignment.self,
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
    func categorySelectionDoesNotRewriteSavedMediaFilter() {
        var configuration = ReviewConfiguration()
        configuration.mediaFilter = .videos
        let request = ReviewRequest(
            configuration: configuration,
            category: .metadata(.screenshots)
        )

        #expect(request.configuration.effectiveMediaFilter == .videos)
        #expect(request.configuration.summary.contains("Videos"))
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
struct GIFAnimationTests {
    @Test
    func decodesFrameTimingAndDownsamplesForPlayback() async throws {
        let data = try GIFTestData.make()
        let animation = try await GIFAnimationDecoder.decode(
            data: data,
            maximumPixelDimension: 50
        )

        #expect(animation.frameCount == 2)
        #expect(abs(animation.totalDuration - 0.35) < 0.01)
        #expect(animation.frameStartTimes[0].doubleValue == 0)
        #expect(
            abs(animation.frameStartTimes[1].doubleValue - (0.1 / 0.35))
                < 0.01
        )
        #expect(animation.frames.allSatisfy { $0.width <= 50 })
        #expect(animation.frames.allSatisfy { $0.height <= 50 })
    }

    @Test
    func rejectsInvalidAnimationData() async {
        await #expect(throws: GIFAnimationError.self) {
            try await GIFAnimationDecoder.decode(
                data: Data("not a gif".utf8),
                maximumPixelDimension: 100
            )
        }
    }

    @Test
    func photoLibraryClientReturnsGIFDataOnlyForMappedAssets() async throws {
        let library = FakePhotoLibraryClient()
        let data = try GIFTestData.make()
        library.gifDataByIdentifier["gif"] = data

        let loadedGIF = try await library.gifData(identifier: "gif")
        let loadedStill = try await library.gifData(identifier: "still")

        #expect(loadedGIF == data)
        #expect(loadedStill == nil)
        #expect(library.gifDataRequests == ["gif", "still"])
    }

    @Test
    func onlyKnownStandaloneGIFsRequestPlaybackData() {
        let gif = MediaAssetDescriptor.fixture(id: "gif", gif: true)
        let still = MediaAssetDescriptor.fixture(id: "still")
        let livePhoto = MediaAssetDescriptor.fixture(
            id: "live",
            livePhoto: true
        )

        #expect(gif.isPlayableGIF)
        #expect(!still.isPlayableGIF)
        #expect(!livePhoto.isPlayableGIF)
    }
}

@MainActor
struct ImageClassificationPolicyTests {
    @Test
    func keepsArbitraryHighPrecisionLabelsOrderedByConfidence() {
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

        #expect(result.tags.map(\.identifier) == ["document", "receipt"])
        #expect(result.tags.map(\.confidence) == [0.99, 0.91])
        #expect(result.classifierVersion == 7)
    }

    @Test
    func filtersNoiseDeduplicatesAndCapsResultsAtFive() {
        let result = ImageClassificationPolicy.resolve(
            candidates: (0..<7).flatMap { index in
                [
                    ClassificationCandidate(
                        identifier: "label-\(index)",
                        confidence: Float(100 - index) / 100,
                        meetsHighPrecision: true
                    ),
                    ClassificationCandidate(
                        identifier: "label-\(index)",
                        confidence: 0.1,
                        meetsHighPrecision: index != 6
                    )
                ]
            } + [
                ClassificationCandidate(
                    identifier: "noise",
                    confidence: 1,
                    meetsHighPrecision: false
                )
            ],
            classifierVersion: 2
        )

        #expect(result.tags.count == 5)
        #expect(
            result.tags.map(\.identifier)
                == ["label-0", "label-1", "label-2", "label-3", "label-4"]
        )
        #expect(!result.tags.map(\.identifier).contains("noise"))
    }

    @Test
    func successfulClassificationCanProduceNoTags() {
        let result = ImageClassificationPolicy.resolve(
            candidates: [
                ClassificationCandidate(
                    identifier: "uncertain",
                    confidence: 0.89,
                    meetsHighPrecision: false
                )
            ],
            classifierVersion: 2
        )

        #expect(result.tags.isEmpty)
        #expect(VisionTag.displayTitle(for: "hot_dog-food") == "Hot Dog Food")
    }
}

@MainActor
struct ClassificationPersistenceTests {
    @Test
    func legacyCategoryConfigurationMigratesToDynamicDashboardDefaults() throws {
        let container = try makeContainer()
        let preference = AppPreference()
        preference.scopeRawValue = ReviewScopeKind.screenshots.rawValue
        preference.mediaFilterRawValue = MediaFilter.videos.rawValue
        preference.categoryRawValue = "receipts"
        container.mainContext.insert(preference)
        try container.mainContext.save()

        let migrated = try ReviewRepository(modelContext: container.mainContext)
            .preference()

        #expect(migrated.scopeRawValue == ReviewScopeKind.unreviewed.rawValue)
        #expect(migrated.configuration.scope == .unreviewed)
        #expect(migrated.configuration.mediaFilter == .photos)
        #expect(migrated.categoryRawValue == "any")
        #expect(
            migrated.minimumVisionCategorySize
                == VisionCategoryDisplayPolicy.defaultMinimumSize
        )
    }

    @Test
    func visionCategoryMinimumPersistsAndNormalizesToSupportedRange() throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)

        let preference = try repository.preference()
        #expect(preference.minimumVisionCategorySize == 5)

        try repository.setMinimumVisionCategorySize(12)
        #expect(try repository.preference().minimumVisionCategorySize == 12)

        try repository.setMinimumVisionCategorySize(0)
        #expect(try repository.preference().minimumVisionCategorySize == 1)

        preference.minimumVisionCategorySize = 500
        try container.mainContext.save()
        #expect(try repository.preference().minimumVisionCategorySize == 50)
    }

    @Test
    func existingClassificationCachePreservesPriorCategorizationOptIn() throws {
        let container = try makeContainer()
        let preference = AppPreference(hasStartedCategorization: false)
        let classification = AssetClassification(
            assetIdentifier: "legacy",
            assetModificationDate: nil,
            classifierVersion: 1,
            status: .classified
        )
        classification.categoryRawValue = "receipts"
        classification.confidence = 0.97
        container.mainContext.insert(preference)
        container.mainContext.insert(classification)
        try container.mainContext.save()

        let migrated = try ReviewRepository(modelContext: container.mainContext)
            .preference()

        #expect(migrated.hasStartedCategorization)
    }

    @Test
    func resetHistoryPreservesTagsButAssetRemovalDoesNot() throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        try repository.markKept(identifier: "receipt")
        try repository.saveClassification(
            identifier: "receipt",
            tags: [
                VisionTag(identifier: "receipt", confidence: 0.95),
                VisionTag(identifier: "document", confidence: 0.91)
            ],
            modificationDate: Date(timeIntervalSince1970: 100),
            classifierVersion: ImageClassificationPolicy.classifierVersion,
            status: .classified
        )

        try repository.resetReviewHistory()
        #expect(
            try repository.visionTagsByAsset()["receipt"]?.map(\.identifier)
                .sorted() == ["document", "receipt"]
        )

        try repository.removeRecords(for: ["receipt"])
        #expect(try repository.classificationSnapshots()["receipt"] == nil)
        #expect(try repository.visionTagsByAsset()["receipt"] == nil)
    }

    @Test
    func replacingClassificationReplacesAllPriorTagsAtomically() throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let date = Date(timeIntervalSince1970: 100)

        try repository.saveClassification(
            identifier: "asset",
            tags: [
                VisionTag(identifier: "dog", confidence: 0.9),
                VisionTag(identifier: "outdoors", confidence: 0.8)
            ],
            modificationDate: date,
            classifierVersion: 2,
            status: .classified
        )
        let update = try repository.saveClassification(
            identifier: "asset",
            tags: [VisionTag(identifier: "cat", confidence: 0.95)],
            modificationDate: date,
            classifierVersion: 2,
            status: .classified
        )

        #expect(update.previousTagIdentifiers == ["dog", "outdoors"])
        #expect(update.tagIdentifiers == ["cat"])
        #expect(
            try repository.visionTagsByAsset()["asset"]?
                .map(\.identifier) == ["cat"]
        )
        #expect(
            try repository.visionTagsByAsset(classifierVersion: 1)["asset"] == nil
        )
        #expect(
            try repository.visionTagsByAsset(classifierVersion: 2)["asset"]?
                .map(\.identifier) == ["cat"]
        )
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
            VisionTagAssignment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

@MainActor
struct CategoryDeckTests {
    @Test
    func metadataAndVisionCategoriesCanOverlap() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let screenshot = MediaAssetDescriptor.fixture(id: "screenshot", screenshot: true)
        let document = MediaAssetDescriptor.fixture(id: "document")
        let library = FakePhotoLibraryClient(
            assets: [screenshot, document]
        )

        try save(
            tags: ["document", "text"],
            asset: screenshot,
            repository: repository
        )
        try save(tags: ["document"], asset: document, repository: repository)

        let screenshotModel = ReviewSessionModel(
            request: ReviewRequest(
                configuration: ReviewConfiguration(),
                category: .metadata(.screenshots)
            ),
            repository: repository,
            photoLibrary: library,
            hapticsEnabled: false
        )
        await screenshotModel.load()

        let documentModel = ReviewSessionModel(
            request: ReviewRequest(
                configuration: ReviewConfiguration(),
                category: .vision("document")
            ),
            repository: repository,
            photoLibrary: library,
            hapticsEnabled: false
        )
        await documentModel.load()

        #expect(screenshotModel.assets.map(\.id) == ["screenshot"])
        #expect(documentModel.assets.map(\.id) == ["screenshot", "document"])
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
            try save(tags: ["receipt"], asset: asset, repository: repository)
        }
        try save(tags: ["document"], asset: document, repository: repository)
        try repository.markKept(identifier: reviewed.id)

        var configuration = ReviewConfiguration()
        configuration.scope = .recent
        configuration.recentDays = 7
        configuration.mediaFilter = .photos
        configuration.order = .newestFirst

        let protectedModel = ReviewSessionModel(
            request: ReviewRequest(
                configuration: configuration,
                category: .vision("receipt")
            ),
            repository: repository,
            photoLibrary: library,
            hapticsEnabled: false
        )
        await protectedModel.load()
        #expect(protectedModel.assets.map(\.id) == ["included"])

        configuration.includeFavorites = true
        configuration.includeReviewed = true
        let inclusiveModel = ReviewSessionModel(
            request: ReviewRequest(
                configuration: configuration,
                category: .vision("receipt")
            ),
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
        tags: [String],
        asset: MediaAssetDescriptor,
        repository: ReviewRepository
    ) throws {
        try repository.saveClassification(
            identifier: asset.id,
            tags: tags.map {
                VisionTag(identifier: $0, confidence: 1)
            },
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
            VisionTagAssignment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

@MainActor
struct CategoryDashboardTests {
    @Test
    func hidesEmptyFacetsAndStreamsVisionBucketCounts() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let photo = MediaAssetDescriptor.fixture(id: "photo", screenshot: true)
        let secondPhoto = MediaAssetDescriptor.fixture(id: "second-photo")
        let video = MediaAssetDescriptor.fixture(id: "video", kind: .video)
        let favorite = MediaAssetDescriptor.fixture(
            id: "favorite",
            favorite: true,
            panorama: true
        )
        let library = FakePhotoLibraryClient(
            assets: [photo, secondPhoto, video, favorite]
        )
        let coordinator = ClassificationCoordinator(
            classifier: FakeImageClassificationClient(
                classifierVersion: ImageClassificationPolicy.classifierVersion,
                results: [
                    photo.id: ImageClassificationResult(
                        tags: [
                            VisionTag(identifier: "dog", confidence: 0.95),
                            VisionTag(
                                identifier: "screenshot",
                                confidence: 0.94
                            )
                        ],
                        classifierVersion: ImageClassificationPolicy.classifierVersion
                    ),
                    secondPhoto.id: ImageClassificationResult(
                        tags: [
                            VisionTag(identifier: "dog", confidence: 0.94),
                            VisionTag(
                                identifier: "screen_shot",
                                confidence: 0.93
                            )
                        ],
                        classifierVersion: ImageClassificationPolicy.classifierVersion
                    )
                ]
            )
        )
        let dashboard = CategoryDashboardModel()

        await dashboard.load(
            configuration: ReviewConfiguration(),
            repository: repository,
            photoLibrary: library,
            coordinator: coordinator,
            minimumVisionCategorySize: 1
        )

        #expect(
            dashboard.metadataBuckets.map(\.category)
                == [
                    .metadata(.images),
                    .metadata(.videos),
                    .metadata(.screenshots)
                ]
        )
        #expect(dashboard.visionBuckets.isEmpty)

        _ = await coordinator.runLocalIndexing(
            repository: repository,
            photoLibrary: library
        )
        for _ in 0..<50
            where dashboard.visionBuckets.first?.count != 2 {
            await Task.yield()
        }

        #expect(dashboard.visionBuckets.first?.category == .vision("dog"))
        #expect(dashboard.visionBuckets.first?.count == 2)
        #expect(dashboard.discoveredVisionCategoryCount == 1)
        #expect(dashboard.visibleVisionCategoryCount == 1)
        #expect(
            !dashboard.visionBuckets.contains {
                $0.category == .vision("screenshot")
                    || $0.category == .vision("screen_shot")
            }
        )
    }

    @Test
    func visionMinimumUsesEligibleCountsAndStreamsTheThresholdMatch() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let photos = (1...5).map {
            MediaAssetDescriptor.fixture(id: "photo-\($0)")
        }
        let result = ImageClassificationResult(
            tags: [VisionTag(identifier: "wine", confidence: 0.95)],
            classifierVersion: ImageClassificationPolicy.classifierVersion
        )
        let classifier = FakeImageClassificationClient(
            classifierVersion: ImageClassificationPolicy.classifierVersion,
            results: Dictionary(
                uniqueKeysWithValues: photos.map { ($0.id, result) }
            )
        )
        let library = FakePhotoLibraryClient(
            assets: Array(photos.prefix(4))
        )
        let coordinator = ClassificationCoordinator(classifier: classifier)
        let dashboard = CategoryDashboardModel()

        await dashboard.load(
            configuration: ReviewConfiguration(),
            repository: repository,
            photoLibrary: library,
            coordinator: coordinator,
            minimumVisionCategorySize: 5
        )
        _ = await coordinator.runLocalIndexing(
            repository: repository,
            photoLibrary: library
        )
        for _ in 0..<50
            where dashboard.discoveredVisionCategoryCount != 1 {
            await Task.yield()
        }

        #expect(
            dashboard.metadataBuckets.first {
                $0.category == .metadata(.images)
            }?.count == 4
        )
        #expect(dashboard.discoveredVisionCategoryCount == 1)
        #expect(dashboard.visionBuckets.isEmpty)

        await dashboard.load(
            configuration: ReviewConfiguration(),
            repository: repository,
            photoLibrary: library,
            coordinator: coordinator,
            minimumVisionCategorySize: 4
        )
        #expect(dashboard.visionBuckets.first?.count == 4)

        library.assets.append(photos[4])
        await dashboard.load(
            configuration: ReviewConfiguration(),
            repository: repository,
            photoLibrary: library,
            coordinator: coordinator,
            minimumVisionCategorySize: 5
        )
        #expect(dashboard.visionBuckets.isEmpty)

        _ = await coordinator.runLocalIndexing(
            repository: repository,
            photoLibrary: library
        )
        for _ in 0..<50
            where dashboard.visionBuckets.first?.count != 5 {
            await Task.yield()
        }

        #expect(dashboard.visionBuckets.first?.category == .vision("wine"))
        #expect(dashboard.visionBuckets.first?.count == 5)

        try repository.markKept(identifier: photos[0].id)
        await dashboard.load(
            configuration: ReviewConfiguration(),
            repository: repository,
            photoLibrary: library,
            coordinator: coordinator,
            minimumVisionCategorySize: 5
        )
        #expect(dashboard.discoveredVisionCategoryCount == 1)
        #expect(dashboard.visionBuckets.isEmpty)
    }

    @Test
    func canceledRefreshDoesNotSurfaceAsADashboardError() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let library = FakePhotoLibraryClient(
            assets: [.fixture(id: "gif", gif: true)]
        )
        library.fetchAssetsDelay = .seconds(1)
        let coordinator = ClassificationCoordinator(
            classifier: FakeImageClassificationClient()
        )
        let dashboard = CategoryDashboardModel()

        let refresh = Task { @MainActor in
            await dashboard.load(
                configuration: ReviewConfiguration(),
                repository: repository,
                photoLibrary: library,
                coordinator: coordinator,
                minimumVisionCategorySize: 5
            )
        }
        await Task.yield()
        refresh.cancel()
        await refresh.value

        #expect(dashboard.errorMessage == nil)
        #expect(!dashboard.isLoading)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ReviewedAsset.self,
            PendingDeletion.self,
            AppPreference.self,
            AssetClassification.self,
            VisionTagAssignment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

@MainActor
struct ClassificationCoordinatorTests {
    @Test
    func allImagesUseVisionAndCloudAssetsRetryInBackground() async throws {
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
                "screenshot": ImageClassificationResult(
                    tags: [
                        VisionTag(identifier: "text", confidence: 0.96)
                    ],
                    classifierVersion: ImageClassificationPolicy.classifierVersion
                ),
                "receipt": ImageClassificationResult(
                    tags: [
                        VisionTag(identifier: "receipt", confidence: 0.94)
                    ],
                    classifierVersion: ImageClassificationPolicy.classifierVersion
                ),
                "cloud-document": ImageClassificationResult(
                    tags: [
                        VisionTag(identifier: "document", confidence: 0.93)
                    ],
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
        var tags = try repository.visionTagsByAsset()
        #expect(tags["screenshot"]?.map(\.identifier) == ["text"])
        #expect(tags["receipt"]?.map(\.identifier) == ["receipt"])
        #expect(snapshots["cloud-document"]?.status == .deferredCloud)
        let classifiedIdentifiers = await probe.identifiers
        #expect(classifiedIdentifiers.contains("screenshot"))

        let completed = await coordinator.runBackgroundIndexing(
            repository: repository,
            photoLibrary: library
        )

        snapshots = try repository.classificationSnapshots()
        tags = try repository.visionTagsByAsset()
        #expect(completed)
        #expect(tags["cloud-document"]?.map(\.identifier) == ["document"])
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
    func reviewModeReducesClassificationConcurrencyToOne() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let library = FakePhotoLibraryClient(
            assets: (0..<6).map { .fixture(id: "review-\($0)") }
        )
        let probe = ClassificationProbe()
        let coordinator = ClassificationCoordinator(
            classifier: FakeImageClassificationClient(
                delay: .milliseconds(10),
                probe: probe
            )
        )
        coordinator.setReviewActive(true)

        _ = await coordinator.runLocalIndexing(
            repository: repository,
            photoLibrary: library
        )

        #expect(await probe.maximumConcurrentCalls == 1)
    }

    @Test
    func photoLibraryChangesSuspendAndResumeAutomaticIndexing() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let assets = (0..<40).map {
            MediaAssetDescriptor.fixture(id: "mutation-\($0)")
        }
        let library = FakePhotoLibraryClient(assets: assets)
        let coordinator = ClassificationCoordinator(
            classifier: FakeImageClassificationClient(
                delay: .milliseconds(20)
            )
        )

        coordinator.startAutomaticIndexing(
            repository: repository,
            photoLibrary: library
        )
        for _ in 0..<100 where !coordinator.isIndexing {
            try await Task.sleep(for: .milliseconds(2))
        }

        #expect(coordinator.isIndexing)
        coordinator.suspendForPhotoLibraryChange()
        let pausedCount = try repository.classificationSnapshots().count

        #expect(!coordinator.isIndexing)
        #expect(pausedCount < assets.count)
        try await Task.sleep(for: .milliseconds(50))
        #expect(try repository.classificationSnapshots().count == pausedCount)

        coordinator.resumeAfterPhotoLibraryChange()
        for _ in 0..<200
            where try repository.classificationSnapshots().count < assets.count {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(try repository.classificationSnapshots().count == assets.count)
    }

    @Test
    func photoLibrarySuspensionDoesNotWaitForVisionCancellation() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let library = FakePhotoLibraryClient(
            assets: [.fixture(id: "non-cooperative")]
        )
        let gate = CancellationIgnoringClassificationGate()
        let classifier = CancellationIgnoringImageClassificationClient(gate: gate)
        let coordinator = ClassificationCoordinator(
            classifier: classifier
        )

        coordinator.startAutomaticIndexing(
            repository: repository,
            photoLibrary: library
        )
        for _ in 0..<100 where !(await gate.isBlockingFirstCall) {
            try await Task.sleep(for: .milliseconds(2))
        }

        #expect(await gate.isBlockingFirstCall)
        coordinator.suspendForPhotoLibraryChange()
        #expect(!coordinator.isIndexing)

        coordinator.resumeAfterPhotoLibraryChange()
        await gate.releaseFirstCall()
        for _ in 0..<100
            where try repository.classificationSnapshots().count < 1 {
            try await Task.sleep(for: .milliseconds(2))
        }

        #expect(try repository.classificationSnapshots().count == 1)
        #expect(await gate.callCount == 2)
    }

    @Test
    func ordinaryCancellationDropsAQueuedAutomaticRestart() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let library = FakePhotoLibraryClient(
            assets: [.fixture(id: "backgrounded")]
        )
        let gate = CancellationIgnoringClassificationGate()
        let classifier = CancellationIgnoringImageClassificationClient(gate: gate)
        let coordinator = ClassificationCoordinator(classifier: classifier)

        coordinator.startAutomaticIndexing(
            repository: repository,
            photoLibrary: library
        )
        for _ in 0..<100 where !(await gate.isBlockingFirstCall) {
            try await Task.sleep(for: .milliseconds(2))
        }

        coordinator.startAutomaticIndexing(
            repository: repository,
            photoLibrary: library
        )
        coordinator.cancelCurrentWork()
        await gate.releaseFirstCall()
        try await Task.sleep(for: .milliseconds(20))

        #expect(await gate.callCount == 1)
        #expect(try repository.classificationSnapshots().isEmpty)
    }

    @Test
    func failedItemsStayUnknownUntilRetried() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let asset = MediaAssetDescriptor.fixture(id: "broken")
        let library = FakePhotoLibraryClient(assets: [asset])
        let failingCoordinator = ClassificationCoordinator(
            classifier: FakeImageClassificationClient(
                failingIdentifiers: ["broken"]
            )
        )
        let failedOutcome = await failingCoordinator.runLocalIndexing(
            repository: repository,
            photoLibrary: library
        )

        #expect(failedOutcome.failedCount == 1)
        #expect(try repository.classificationSnapshots()["broken"]?.status == .failed)

        try failingCoordinator.retryFailed(repository: repository)
        let successfulCoordinator = ClassificationCoordinator(
            classifier: FakeImageClassificationClient()
        )
        let successOutcome = await successfulCoordinator.runLocalIndexing(
            repository: repository,
            photoLibrary: library
        )

        #expect(successOutcome.failedCount == 0)
        #expect(try repository.classificationSnapshots()["broken"]?.status == .classified)
        #expect(try repository.visionTagsByAsset()["broken"] == nil)
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
        let scan = Task { @MainActor in
            await coordinator.runLocalIndexing(
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
        scan.cancel()
        let outcome = await scan.value
        let savedCount = try repository.classificationSnapshots().count

        #expect(outcome.wasCanceled)
        #expect(savedCount >= 2)
        #expect(savedCount < library.assets.count)
    }

    @Test
    func activeVisionDeckAppendsMatchesWithoutReplacingCurrentCard() async throws {
        let container = try makeContainer()
        let repository = ReviewRepository(modelContext: container.mainContext)
        let first = MediaAssetDescriptor.fixture(
            id: "first",
            date: Date(timeIntervalSince1970: 100)
        )
        let second = MediaAssetDescriptor.fixture(
            id: "second",
            date: Date(timeIntervalSince1970: 200)
        )
        let library = FakePhotoLibraryClient(assets: [first, second])
        let result = ImageClassificationResult(
            tags: [VisionTag(identifier: "dog", confidence: 0.95)],
            classifierVersion: ImageClassificationPolicy.classifierVersion
        )
        let coordinator = ClassificationCoordinator(
            classifier: FakeImageClassificationClient(
                results: ["first": result, "second": result],
                delay: .milliseconds(20)
            )
        )
        coordinator.setReviewActive(true)
        let model = ReviewSessionModel(
            request: ReviewRequest(
                configuration: ReviewConfiguration(),
                category: .vision("dog")
            ),
            repository: repository,
            photoLibrary: library,
            classificationCoordinator: coordinator,
            hapticsEnabled: false
        )
        await model.load()
        #expect(model.assets.isEmpty)

        let scan = Task { @MainActor in
            await coordinator.runLocalIndexing(
                repository: repository,
                photoLibrary: library
            )
        }
        for _ in 0..<100 where model.assets.isEmpty {
            try await Task.sleep(for: .milliseconds(2))
        }
        let firstVisibleIdentifier = model.currentAsset?.id
        for _ in 0..<100 where model.assets.count < 2 {
            try await Task.sleep(for: .milliseconds(2))
        }
        _ = await scan.value

        #expect(firstVisibleIdentifier == "first")
        #expect(model.currentAsset?.id == firstVisibleIdentifier)
        #expect(model.assets.map(\.id) == ["first", "second"])
        #expect(model.positionText == "1 of 2")
        model.endSession()
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
            tags: [VisionTag(identifier: "document", confidence: 0.95)],
            modificationDate: oldDate,
            classifierVersion: ImageClassificationPolicy.classifierVersion,
            status: .classified
        )
        let coordinator = ClassificationCoordinator(
            classifier: FakeImageClassificationClient(
                results: [
                    modified.id: ImageClassificationResult(
                        tags: [
                            VisionTag(identifier: "receipt", confidence: 0.96)
                        ],
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
        #expect(snapshot?.assetModificationDate == newDate)
        #expect(
            try repository.visionTagsByAsset()[modified.id]?
                .map(\.identifier) == ["receipt"]
        )
        #expect(library.classificationRequests.map(\.identifier) == [modified.id])
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ReviewedAsset.self,
            PendingDeletion.self,
            AppPreference.self,
            AssetClassification.self,
            VisionTagAssignment.self,
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
