import Foundation
@preconcurrency import Photos

actor PhotoKitCatalog {
    func fetchAssets(
        configuration: ReviewConfiguration,
        reviewedIdentifiers: Set<String>,
        pendingIdentifiers: Set<String>
    ) throws -> [MediaAssetDescriptor] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false

        var predicates: [NSPredicate] = []

        switch configuration.effectiveMediaFilter {
        case .all:
            predicates.append(
                NSPredicate(
                    format: "mediaType == %d OR mediaType == %d",
                    PHAssetMediaType.image.rawValue,
                    PHAssetMediaType.video.rawValue
                )
            )
        case .photos:
            predicates.append(
                NSPredicate(
                    format: "mediaType == %d",
                    PHAssetMediaType.image.rawValue
                )
            )
        case .videos:
            predicates.append(
                NSPredicate(
                    format: "mediaType == %d",
                    PHAssetMediaType.video.rawValue
                )
            )
        }

        if configuration.category == .screenshots {
            predicates.append(
                NSPredicate(
                    format: "(mediaSubtype & %d) != 0",
                    PHAssetMediaSubtype.photoScreenshot.rawValue
                )
            )
        }

        if let range = configuration.normalizedDateRange {
            predicates.append(
                NSPredicate(
                    format: "creationDate >= %@ AND creationDate <= %@",
                    range.lowerBound as NSDate,
                    range.upperBound as NSDate
                )
            )
        }

        if !configuration.includeFavorites {
            predicates.append(NSPredicate(format: "favorite == NO"))
        }

        options.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: predicates
        )
        options.sortDescriptors = [
            NSSortDescriptor(
                key: "creationDate",
                ascending: configuration.order == .oldestFirst
            )
        ]

        let fetchResult = PHAsset.fetchAssets(with: options)
        var descriptors: [MediaAssetDescriptor] = []
        descriptors.reserveCapacity(fetchResult.count)

        fetchResult.enumerateObjects { asset, _, stop in
            if Task.isCancelled {
                stop.pointee = true
                return
            }

            let identifier = asset.localIdentifier
            guard !pendingIdentifiers.contains(identifier) else { return }

            let shouldExcludeReviewed =
                configuration.scope == .unreviewed || !configuration.includeReviewed
            guard !shouldExcludeReviewed
                    || !reviewedIdentifiers.contains(identifier) else {
                return
            }

            if let descriptor = MediaAssetDescriptor(asset: asset) {
                descriptors.append(descriptor)
            }
        }
        try Task.checkCancellation()

        return descriptors.sorted { lhs, rhs in
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

    func classifiableAssets() throws -> [MediaAssetDescriptor] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false
        options.predicate = NSPredicate(
            format: "mediaType == %d",
            PHAssetMediaType.image.rawValue
        )
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]

        let result = PHAsset.fetchAssets(with: options)
        var descriptors: [MediaAssetDescriptor] = []
        descriptors.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, stop in
            if Task.isCancelled {
                stop.pointee = true
                return
            }
            if let descriptor = MediaAssetDescriptor(asset: asset) {
                descriptors.append(descriptor)
            }
        }
        try Task.checkCancellation()
        return descriptors
    }

    func descriptors(for identifiers: [String]) -> [MediaAssetDescriptor] {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: identifiers,
            options: nil
        )
        var byIdentifier: [String: MediaAssetDescriptor] = [:]
        result.enumerateObjects { asset, _, _ in
            if let descriptor = MediaAssetDescriptor(asset: asset) {
                byIdentifier[descriptor.id] = descriptor
            }
        }
        return identifiers.compactMap { byIdentifier[$0] }
    }
}
