import Foundation
import SwiftData

@Model
final class ReviewedAsset {
    @Attribute(.unique) var assetIdentifier: String
    var lastReviewedAt: Date

    init(assetIdentifier: String, lastReviewedAt: Date = .now) {
        self.assetIdentifier = assetIdentifier
        self.lastReviewedAt = lastReviewedAt
    }
}

@Model
final class PendingDeletion {
    @Attribute(.unique) var assetIdentifier: String
    var sourceRawValue: String
    var queuedAt: Date

    var source: PendingDeletionSource {
        get { PendingDeletionSource(rawValue: sourceRawValue) ?? .swipe }
        set { sourceRawValue = newValue.rawValue }
    }

    init(
        assetIdentifier: String,
        source: PendingDeletionSource,
        queuedAt: Date = .now
    ) {
        self.assetIdentifier = assetIdentifier
        self.sourceRawValue = source.rawValue
        self.queuedAt = queuedAt
    }
}

@Model
final class AppPreference {
    @Attribute(.unique) var key: String
    var hasCompletedOnboarding: Bool
    var scopeRawValue: String
    var recentDays: Int
    var customStart: Date
    var customEnd: Date
    var mediaFilterRawValue: String
    var categoryRawValue: String = "any"
    var orderRawValue: String
    var includeReviewed: Bool
    var includeFavorites: Bool
    var hapticsEnabled: Bool
    var hasStartedCategorization: Bool = false

    init(
        key: String = "primary",
        hasCompletedOnboarding: Bool = false,
        configuration: ReviewConfiguration = ReviewConfiguration(),
        hapticsEnabled: Bool = true,
        hasStartedCategorization: Bool = false
    ) {
        self.key = key
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.scopeRawValue = configuration.scope.rawValue
        self.recentDays = configuration.recentDays
        self.customStart = configuration.customStart
        self.customEnd = configuration.customEnd
        self.mediaFilterRawValue = configuration.mediaFilter.rawValue
        self.categoryRawValue = "any"
        self.orderRawValue = configuration.order.rawValue
        self.includeReviewed = configuration.includeReviewed
        self.includeFavorites = configuration.includeFavorites
        self.hapticsEnabled = hapticsEnabled
        self.hasStartedCategorization = hasStartedCategorization
    }

    var configuration: ReviewConfiguration {
        get {
            let isLegacyScreenshotScope = scopeRawValue == ReviewScopeKind.screenshots.rawValue
            return ReviewConfiguration(
                scope: isLegacyScreenshotScope
                    ? .unreviewed
                    : ReviewScopeKind(rawValue: scopeRawValue) ?? .unreviewed,
                recentDays: recentDays,
                customStart: customStart,
                customEnd: customEnd,
                mediaFilter: MediaFilter(rawValue: mediaFilterRawValue) ?? .all,
                order: ReviewOrder(rawValue: orderRawValue) ?? .oldestFirst,
                includeReviewed: includeReviewed,
                includeFavorites: includeFavorites
            )
        }
        set {
            scopeRawValue = newValue.scope.rawValue
            recentDays = newValue.recentDays
            customStart = newValue.customStart
            customEnd = newValue.customEnd
            mediaFilterRawValue = newValue.mediaFilter.rawValue
            categoryRawValue = "any"
            orderRawValue = newValue.order.rawValue
            includeReviewed = newValue.includeReviewed
            includeFavorites = newValue.includeFavorites
        }
    }

    func migrateLegacyCategoryConfiguration() -> Bool {
        var changed = false
        if scopeRawValue == ReviewScopeKind.screenshots.rawValue {
            scopeRawValue = ReviewScopeKind.unreviewed.rawValue
            mediaFilterRawValue = MediaFilter.photos.rawValue
            includeReviewed = false
            changed = true
        }
        if categoryRawValue != "any" {
            categoryRawValue = "any"
            changed = true
        }
        return changed
    }
}

@Model
final class AssetClassification {
    @Attribute(.unique) var assetIdentifier: String
    var categoryRawValue: String?
    var confidence: Float
    var assetModificationDate: Date?
    var classifierVersion: Int
    var statusRawValue: String
    var lastAttemptAt: Date

    var status: ClassificationRecordStatus {
        get {
            ClassificationRecordStatus(rawValue: statusRawValue) ?? .failed
        }
        set {
            statusRawValue = newValue.rawValue
        }
    }

    init(
        assetIdentifier: String,
        assetModificationDate: Date?,
        classifierVersion: Int,
        status: ClassificationRecordStatus,
        lastAttemptAt: Date = .now
    ) {
        self.assetIdentifier = assetIdentifier
        self.categoryRawValue = nil
        self.confidence = 0
        self.assetModificationDate = assetModificationDate
        self.classifierVersion = classifierVersion
        self.statusRawValue = status.rawValue
        self.lastAttemptAt = lastAttemptAt
    }

    var snapshot: ClassificationCacheSnapshot {
        ClassificationCacheSnapshot(
            assetIdentifier: assetIdentifier,
            assetModificationDate: assetModificationDate,
            classifierVersion: classifierVersion,
            status: status,
            lastAttemptAt: lastAttemptAt
        )
    }
}

@Model
final class VisionTagAssignment {
    @Attribute(.unique) var assignmentKey: String
    var assetIdentifier: String
    var tagIdentifier: String
    var confidence: Float
    var classifierVersion: Int

    init(
        assetIdentifier: String,
        tag: VisionTag,
        classifierVersion: Int
    ) {
        self.assignmentKey = Self.key(
            assetIdentifier: assetIdentifier,
            tagIdentifier: tag.identifier
        )
        self.assetIdentifier = assetIdentifier
        self.tagIdentifier = tag.identifier
        self.confidence = tag.confidence
        self.classifierVersion = classifierVersion
    }

    static func key(
        assetIdentifier: String,
        tagIdentifier: String
    ) -> String {
        "\(assetIdentifier)\u{1F}\(tagIdentifier)"
    }

    var tag: VisionTag {
        VisionTag(identifier: tagIdentifier, confidence: confidence)
    }
}
