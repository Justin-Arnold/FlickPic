import Foundation
import Observation

struct CategoryBucket: Identifiable {
    let category: ReviewCategory
    let count: Int
    let representativeAsset: MediaAssetDescriptor

    var id: String { category.id }
}

@Observable
@MainActor
final class CategoryDashboardModel {
    private(set) var metadataBuckets: [CategoryBucket] = []
    private(set) var visionBuckets: [CategoryBucket] = []
    private(set) var discoveredVisionCategoryCount = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var eligibleAssets: [MediaAssetDescriptor] = []
    private var eligibleIdentifiers: Set<String> = []
    private var visionIdentifiersByAsset: [String: Set<String>] = [:]
    private var repository: ReviewRepository?
    private weak var photoLibrary: (any PhotoLibraryClient)?
    private weak var coordinator: ClassificationCoordinator?
    private var configuration = ReviewConfiguration()
    private var minimumVisionCategorySize =
        VisionCategoryDisplayPolicy.defaultMinimumSize
    private var updatesTask: Task<Void, Never>?

    var visibleVisionCategoryCount: Int {
        visionBuckets.count
    }

    func load(
        configuration: ReviewConfiguration,
        repository: ReviewRepository,
        photoLibrary: any PhotoLibraryClient,
        coordinator: ClassificationCoordinator,
        minimumVisionCategorySize: Int
    ) async {
        self.configuration = configuration
        self.repository = repository
        self.photoLibrary = photoLibrary
        self.coordinator = coordinator
        self.minimumVisionCategorySize =
            VisionCategoryDisplayPolicy.normalizedMinimumSize(
                minimumVisionCategorySize
            )
        beginObservingUpdatesIfNeeded(coordinator: coordinator)

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let reviewed = try repository.reviewedIdentifiers()
            let pending = try repository.pendingIdentifiers()
            eligibleAssets = try await photoLibrary.fetchAssets(
                configuration: configuration,
                reviewedIdentifiers: reviewed,
                pendingIdentifiers: pending
            )
            eligibleIdentifiers = Set(eligibleAssets.map(\.id))
            visionIdentifiersByAsset = try repository
                .visionTagsByAsset(
                    restrictedTo: eligibleIdentifiers,
                    classifierVersion: coordinator.classifierVersion
                )
                .mapValues { Set($0.map(\.identifier)) }
            rebuildBuckets()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginObservingUpdatesIfNeeded(
        coordinator: ClassificationCoordinator
    ) {
        guard updatesTask == nil else { return }
        let updates = coordinator.updates()
        updatesTask = Task { @MainActor [weak self] in
            for await update in updates {
                guard let self else { return }
                await self.apply(update)
            }
        }
    }

    private func apply(_ update: ClassificationIndexUpdate) async {
        guard let repository, let photoLibrary, let coordinator else { return }
        if update.kind == .reset {
            await load(
                configuration: configuration,
                repository: repository,
                photoLibrary: photoLibrary,
                coordinator: coordinator,
                minimumVisionCategorySize: minimumVisionCategorySize
            )
            return
        }

        guard let identifier = update.assetIdentifier,
              eligibleIdentifiers.contains(identifier) else {
            return
        }
        visionIdentifiersByAsset[identifier] = update.tagIdentifiers
        rebuildBuckets()
    }

    private func rebuildBuckets() {
        metadataBuckets = MetadataCategory.allCases.compactMap { category in
            let matches = eligibleAssets.filter(category.matches)
            guard let representative = matches.first else { return nil }
            return CategoryBucket(
                category: .metadata(category),
                count: matches.count,
                representativeAsset: representative
            )
        }

        var counts: [String: Int] = [:]
        var representatives: [String: MediaAssetDescriptor] = [:]
        for asset in eligibleAssets {
            for identifier in visionIdentifiersByAsset[asset.id] ?? [] {
                counts[identifier, default: 0] += 1
                representatives[identifier] = representatives[identifier] ?? asset
            }
        }

        discoveredVisionCategoryCount = counts.count
        visionBuckets = counts.compactMap { identifier, count in
            guard count >= minimumVisionCategorySize,
                  let representative = representatives[identifier] else {
                return nil
            }
            return CategoryBucket(
                category: .vision(identifier),
                count: count,
                representativeAsset: representative
            )
        }
        .sorted {
            if $0.count != $1.count {
                return $0.count > $1.count
            }
            return $0.category.title.localizedCaseInsensitiveCompare(
                $1.category.title
            ) == .orderedAscending
        }
    }
}
