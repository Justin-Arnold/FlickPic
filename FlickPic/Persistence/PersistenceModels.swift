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
    var categoryRawValue: String = ContentCategoryFilter.any.rawValue
    var orderRawValue: String
    var includeReviewed: Bool
    var includeFavorites: Bool
    var hapticsEnabled: Bool

    init(
        key: String = "primary",
        hasCompletedOnboarding: Bool = false,
        configuration: ReviewConfiguration = ReviewConfiguration(),
        hapticsEnabled: Bool = true
    ) {
        self.key = key
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.scopeRawValue = configuration.scope.rawValue
        self.recentDays = configuration.recentDays
        self.customStart = configuration.customStart
        self.customEnd = configuration.customEnd
        self.mediaFilterRawValue = configuration.mediaFilter.rawValue
        self.categoryRawValue = configuration.category.rawValue
        self.orderRawValue = configuration.order.rawValue
        self.includeReviewed = configuration.includeReviewed
        self.includeFavorites = configuration.includeFavorites
        self.hapticsEnabled = hapticsEnabled
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
                category: isLegacyScreenshotScope
                    ? .screenshots
                    : ContentCategoryFilter(rawValue: categoryRawValue) ?? .any,
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
            categoryRawValue = newValue.category.rawValue
            orderRawValue = newValue.order.rawValue
            includeReviewed = newValue.includeReviewed
            includeFavorites = newValue.includeFavorites
        }
    }

    func migrateLegacyScreenshotConfiguration() -> Bool {
        guard scopeRawValue == ReviewScopeKind.screenshots.rawValue else {
            return false
        }
        scopeRawValue = ReviewScopeKind.unreviewed.rawValue
        categoryRawValue = ContentCategoryFilter.screenshots.rawValue
        mediaFilterRawValue = MediaFilter.photos.rawValue
        includeReviewed = false
        return true
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

    var category: ContentCategory? {
        get {
            categoryRawValue.flatMap(ContentCategory.init(rawValue:))
        }
        set {
            categoryRawValue = newValue?.rawValue
        }
    }

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
        category: ContentCategory?,
        confidence: Float,
        assetModificationDate: Date?,
        classifierVersion: Int,
        status: ClassificationRecordStatus,
        lastAttemptAt: Date = .now
    ) {
        self.assetIdentifier = assetIdentifier
        self.categoryRawValue = category?.rawValue
        self.confidence = confidence
        self.assetModificationDate = assetModificationDate
        self.classifierVersion = classifierVersion
        self.statusRawValue = status.rawValue
        self.lastAttemptAt = lastAttemptAt
    }

    var snapshot: ClassificationCacheSnapshot {
        ClassificationCacheSnapshot(
            assetIdentifier: assetIdentifier,
            category: category,
            confidence: confidence,
            assetModificationDate: assetModificationDate,
            classifierVersion: classifierVersion,
            status: status,
            lastAttemptAt: lastAttemptAt
        )
    }
}
