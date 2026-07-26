import Foundation

enum ReviewCategory: Hashable, Identifiable, Sendable {
    case metadata(MetadataCategory)
    case vision(String)

    var id: String {
        switch self {
        case let .metadata(category):
            "metadata:\(category.rawValue)"
        case let .vision(identifier):
            "vision:\(identifier)"
        }
    }

    var title: String {
        switch self {
        case let .metadata(category):
            category.title
        case let .vision(identifier):
            VisionTag.displayTitle(for: identifier)
        }
    }

    var systemImage: String {
        switch self {
        case let .metadata(category):
            category.systemImage
        case .vision:
            "sparkles"
        }
    }
}

struct ReviewRequest: Equatable, Sendable {
    var configuration: ReviewConfiguration
    var category: ReviewCategory?

    init(
        configuration: ReviewConfiguration,
        category: ReviewCategory? = nil
    ) {
        self.configuration = configuration
        self.category = category
    }

    func matchesCategory(
        asset: MediaAssetDescriptor,
        visionTagIdentifiers: Set<String>
    ) -> Bool {
        switch category {
        case nil:
            true
        case let .metadata(category):
            category.matches(asset)
        case let .vision(identifier):
            asset.mediaKind == .photo
                && visionTagIdentifiers.contains(identifier)
        }
    }
}

enum ClassificationRecordStatus: String, Codable, Sendable {
    case classified
    case deferredCloud
    case failed
}

struct VisionTag: Equatable, Hashable, Sendable {
    let identifier: String
    let confidence: Float

    var title: String {
        Self.displayTitle(for: identifier)
    }

    static func displayTitle(for identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

nonisolated enum VisionCategoryDisplayPolicy {
    static let defaultMinimumSize = 5
    static let minimumSizeRange = 1...50

    static func normalizedMinimumSize(_ value: Int) -> Int {
        min(
            max(value, minimumSizeRange.lowerBound),
            minimumSizeRange.upperBound
        )
    }
}

struct ImageClassificationResult: Equatable, Sendable {
    let tags: [VisionTag]
    let classifierVersion: Int
}

struct ClassificationCacheSnapshot: Equatable, Sendable {
    let assetIdentifier: String
    let assetModificationDate: Date?
    let classifierVersion: Int
    let status: ClassificationRecordStatus
    let lastAttemptAt: Date

    func isCurrent(
        for descriptor: MediaAssetDescriptor,
        classifierVersion: Int
    ) -> Bool {
        self.classifierVersion == classifierVersion
            && assetModificationDate == descriptor.modificationDate
    }
}

struct ClassificationIndexUpdate: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case asset
        case reset
    }

    let kind: Kind
    let assetIdentifier: String?
    let previousTagIdentifiers: Set<String>
    let tagIdentifiers: Set<String>

    static let reset = ClassificationIndexUpdate(
        kind: .reset,
        assetIdentifier: nil,
        previousTagIdentifiers: [],
        tagIdentifiers: []
    )
}

enum ClassificationImageError: LocalizedError, Equatable {
    case unavailableLocally
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailableLocally:
            "This image needs to be retrieved from iCloud before it can be categorized."
        case .unavailable:
            "FlickPic could not prepare this image for on-device categorization."
        }
    }
}
