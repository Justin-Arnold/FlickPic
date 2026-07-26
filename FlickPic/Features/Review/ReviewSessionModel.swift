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
    let configuration: ReviewConfiguration

    private let repository: ReviewRepository
    private let photoLibrary: any PhotoLibraryClient
    private let hapticsEnabled: Bool

    private(set) var assets: [MediaAssetDescriptor] = []
    private(set) var isLoading = false
    var errorMessage: String?
    private(set) var pendingCount = 0
    private(set) var processedCount = 0
    private(set) var initialAssetCount = 0
    private(set) var actionHistory: [ActionRecord] = []
    private(set) var hasEnded = false

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

    init(
        configuration: ReviewConfiguration,
        repository: ReviewRepository,
        photoLibrary: any PhotoLibraryClient,
        hapticsEnabled: Bool
    ) {
        self.configuration = configuration
        self.repository = repository
        self.photoLibrary = photoLibrary
        self.hapticsEnabled = hapticsEnabled
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let reviewed = try repository.reviewedIdentifiers()
            let pending = try repository.pendingIdentifiers()
            let fetched = try await photoLibrary.fetchAssets(
                configuration: configuration,
                reviewedIdentifiers: reviewed,
                pendingIdentifiers: pending
            )
            let classifications = try repository.classificationSnapshots()
            let filtered = fetched.filter { asset in
                let snapshot = classifications[asset.id]
                let indexedCategory: ContentCategory?
                if snapshot?.status == .classified,
                   snapshot?.isCurrent(
                    for: asset,
                    classifierVersion: ImageClassificationPolicy.classifierVersion
                   ) == true {
                    indexedCategory = snapshot?.category
                } else {
                    indexedCategory = nil
                }
                return configuration.matchesCategory(
                    asset: asset,
                    indexedCategory: indexedCategory
                )
            }
            assets = filtered
            initialAssetCount = filtered.count
            pendingCount = pending.count
            preheatUpcomingAssets()
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
        processedCount = 0
        initialAssetCount = 0
        actionHistory.removeAll()
        await load()
    }

    func endSession() {
        hasEnded = true
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

    private func provideFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
