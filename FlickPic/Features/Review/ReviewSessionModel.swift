import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class ReviewSessionModel: Identifiable {
    struct ActionRecord {
        let asset: MediaAssetDescriptor
        let previousState: AssetReviewState
        let processedBeforeAction: Int
    }

    let id = UUID()
    let request: ReviewRequest

    private let repository: ReviewRepository
    private let photoLibrary: any PhotoLibraryClient
    private weak var classificationCoordinator: ClassificationCoordinator?
    private let hapticsEnabled: Bool
    private var eligibleAssetsByIdentifier: [String: MediaAssetDescriptor] = [:]
    private var visionIdentifiersByAsset: [String: Set<String>] = [:]
    private var handledIdentifiers: Set<String> = []
    private var updatesStream: AsyncStream<ClassificationIndexUpdate>?
    private var updatesTask: Task<Void, Never>?

    private(set) var assets: [MediaAssetDescriptor] = []
    private(set) var isLoading = false
    var errorMessage: String?
    private(set) var pendingCount = 0
    private(set) var processedCount = 0
    private(set) var initialAssetCount = 0
    private(set) var actionHistory: [ActionRecord] = []
    private(set) var hasEnded = false

    var configuration: ReviewConfiguration {
        request.configuration
    }

    var currentAsset: MediaAssetDescriptor? {
        assets.first
    }

    var canUndo: Bool {
        !actionHistory.isEmpty
    }

    var positionText: String? {
        guard currentAsset != nil, initialAssetCount > 0 else { return nil }
        return "\(min(processedCount + 1, initialAssetCount)) of \(initialAssetCount)"
    }

    var isWaitingForMoreMatches: Bool {
        guard case .vision = request.category,
              currentAsset == nil,
              classificationCoordinator?.isIndexing == true else {
            return false
        }
        return true
    }

    init(
        request: ReviewRequest,
        repository: ReviewRepository,
        photoLibrary: any PhotoLibraryClient,
        classificationCoordinator: ClassificationCoordinator? = nil,
        hapticsEnabled: Bool
    ) {
        self.request = request
        self.repository = repository
        self.photoLibrary = photoLibrary
        self.classificationCoordinator = classificationCoordinator
        self.hapticsEnabled = hapticsEnabled
        if case .vision = request.category {
            updatesStream = classificationCoordinator?.updates()
        }
    }

    convenience init(
        configuration: ReviewConfiguration,
        repository: ReviewRepository,
        photoLibrary: any PhotoLibraryClient,
        classificationCoordinator: ClassificationCoordinator? = nil,
        hapticsEnabled: Bool
    ) {
        self.init(
            request: ReviewRequest(configuration: configuration),
            repository: repository,
            photoLibrary: photoLibrary,
            classificationCoordinator: classificationCoordinator,
            hapticsEnabled: hapticsEnabled
        )
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let reviewed = try repository.reviewedIdentifiers()
            let pending = try repository.pendingIdentifiers()
            let fetched = try await photoLibrary.fetchAssets(
                configuration: request.configuration,
                reviewedIdentifiers: reviewed,
                pendingIdentifiers: pending
            )
            eligibleAssetsByIdentifier = Dictionary(
                uniqueKeysWithValues: fetched.map { ($0.id, $0) }
            )
            visionIdentifiersByAsset = try repository
                .visionTagsByAsset(
                    restrictedTo: Set(eligibleAssetsByIdentifier.keys),
                    classifierVersion: classificationCoordinator?.classifierVersion
                )
                .mapValues { Set($0.map(\.identifier)) }
            let filtered = fetched.filter { asset in
                request.matchesCategory(
                    asset: asset,
                    visionTagIdentifiers: visionIdentifiersByAsset[asset.id] ?? []
                )
            }
            assets = filtered
            initialAssetCount = filtered.count
            pendingCount = pending.count
            preheatUpcomingAssets()
            beginObservingUpdatesIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    @discardableResult
    func keepCurrent(expectedIdentifier: String? = nil) -> Bool {
        guard !hasEnded else { return false }
        guard let asset = currentAsset else { return false }
        guard expectedIdentifier == nil || expectedIdentifier == asset.id else {
            return false
        }

        do {
            let previousState = try repository.state(for: asset.id)
            try repository.markKept(identifier: asset.id)
            recordAndAdvance(asset: asset, previousState: previousState)
            provideFeedback(.medium)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func queueCurrentForDeletion(
        source: PendingDeletionSource = .swipe,
        expectedIdentifier: String? = nil
    ) -> Bool {
        guard !hasEnded else { return false }
        guard let asset = currentAsset else { return false }
        guard expectedIdentifier == nil || expectedIdentifier == asset.id else {
            return false
        }

        do {
            let previousState = try repository.state(for: asset.id)
            try repository.queueDeletion(identifier: asset.id, source: source)
            recordAndAdvance(asset: asset, previousState: previousState)
            pendingCount = try repository.pendingIdentifiers().count
            provideFeedback(.rigid)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func moveCurrentToLater() {
        guard assets.count > 1 else { return }
        let first = assets.removeFirst()
        assets.append(first)
        provideFeedback(.light)
        preheatUpcomingAssets()
    }

    func undoLastDecision() {
        guard let action = actionHistory.popLast() else { return }

        do {
            try repository.restore(
                identifier: action.asset.id,
                to: action.previousState
            )
            handledIdentifiers.remove(action.asset.id)
            assets.insert(action.asset, at: 0)
            processedCount = action.processedBeforeAction
            pendingCount = try repository.pendingIdentifiers().count
            provideFeedback(.soft)
            preheatUpcomingAssets()
        } catch {
            actionHistory.append(action)
            errorMessage = error.localizedDescription
        }
    }

    func retry() async {
        assets.removeAll()
        eligibleAssetsByIdentifier.removeAll()
        visionIdentifiersByAsset.removeAll()
        handledIdentifiers.removeAll()
        processedCount = 0
        initialAssetCount = 0
        actionHistory.removeAll()
        await load()
    }

    func endSession() {
        hasEnded = true
        updatesTask?.cancel()
        updatesTask = nil
        photoLibrary.stopPreheating()
    }

    private func recordAndAdvance(
        asset: MediaAssetDescriptor,
        previousState: AssetReviewState
    ) {
        actionHistory.append(
            ActionRecord(
                asset: asset,
                previousState: previousState,
                processedBeforeAction: processedCount
            )
        )
        handledIdentifiers.insert(asset.id)
        assets.removeFirst()
        processedCount += 1
        preheatUpcomingAssets()
    }

    private func preheatUpcomingAssets() {
        let identifiers = assets.prefix(3).map(\.id)
        photoLibrary.preheat(
            identifiers: identifiers,
            targetSize: CGSize(width: 1_200, height: 1_600)
        )
    }

    private func beginObservingUpdatesIfNeeded() {
        guard updatesTask == nil, let updatesStream else { return }
        updatesTask = Task { @MainActor [weak self] in
            for await update in updatesStream {
                guard let self, !self.hasEnded else { return }
                self.apply(update)
            }
        }
    }

    private func apply(_ update: ClassificationIndexUpdate) {
        guard case let .vision(selectedIdentifier) = request.category else {
            return
        }

        if update.kind == .reset {
            do {
                visionIdentifiersByAsset = try repository
                    .visionTagsByAsset(
                        restrictedTo: Set(eligibleAssetsByIdentifier.keys),
                        classifierVersion: classificationCoordinator?.classifierVersion
                    )
                    .mapValues { Set($0.map(\.identifier)) }
                reconcileAllAssets(selectedIdentifier: selectedIdentifier)
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        guard let identifier = update.assetIdentifier,
              let asset = eligibleAssetsByIdentifier[identifier] else {
            return
        }
        visionIdentifiersByAsset[identifier] = update.tagIdentifiers
        reconcile(
            asset: asset,
            matches: update.tagIdentifiers.contains(selectedIdentifier)
        )
    }

    private func reconcileAllAssets(selectedIdentifier: String) {
        for asset in eligibleAssetsByIdentifier.values {
            reconcile(
                asset: asset,
                matches: visionIdentifiersByAsset[asset.id]?
                    .contains(selectedIdentifier) == true
            )
        }
    }

    private func reconcile(asset: MediaAssetDescriptor, matches: Bool) {
        let existingIndex = assets.firstIndex(where: { $0.id == asset.id })
        if matches {
            guard existingIndex == nil,
                  !handledIdentifiers.contains(asset.id) else {
                return
            }
            insertNewMatch(asset)
            initialAssetCount += 1
            preheatUpcomingAssets()
        } else if let existingIndex,
                  existingIndex != assets.startIndex {
            assets.remove(at: existingIndex)
            initialAssetCount = max(processedCount, initialAssetCount - 1)
            preheatUpcomingAssets()
        }
    }

    private func insertNewMatch(_ asset: MediaAssetDescriptor) {
        guard let current = assets.first else {
            assets = [asset]
            return
        }

        var remaining = Array(assets.dropFirst())
        remaining.append(asset)
        remaining.sort(by: assetsAreInConfiguredOrder)
        assets = [current] + remaining
    }

    private func assetsAreInConfiguredOrder(
        _ lhs: MediaAssetDescriptor,
        _ rhs: MediaAssetDescriptor
    ) -> Bool {
        switch (lhs.creationDate, rhs.creationDate) {
        case let (left?, right?) where left != right:
            return request.configuration.order == .oldestFirst
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

    private func provideFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
