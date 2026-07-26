import Foundation
import SwiftData

@MainActor
struct ReviewRepository {
    let modelContext: ModelContext

    func preference() throws -> AppPreference {
        var descriptor = FetchDescriptor<AppPreference>(
            predicate: #Predicate { $0.key == "primary" }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            if existing.migrateLegacyScreenshotConfiguration() {
                try modelContext.save()
            }
            return existing
        }

        let preference = AppPreference()
        modelContext.insert(preference)
        try modelContext.save()
        return preference
    }

    func saveConfiguration(_ configuration: ReviewConfiguration) throws {
        let preference = try preference()
        preference.configuration = configuration
        try modelContext.save()
    }

    func completeOnboarding() throws {
        let preference = try preference()
        preference.hasCompletedOnboarding = true
        try modelContext.save()
    }

    func setHapticsEnabled(_ isEnabled: Bool) throws {
        let preference = try preference()
        preference.hapticsEnabled = isEnabled
        try modelContext.save()
    }

    func reviewedIdentifiers() throws -> Set<String> {
        Set(try modelContext.fetch(FetchDescriptor<ReviewedAsset>()).map(\.assetIdentifier))
    }

    func pendingIdentifiers() throws -> Set<String> {
        Set(try modelContext.fetch(FetchDescriptor<PendingDeletion>()).map(\.assetIdentifier))
    }

    func pendingItems() throws -> [PendingDeletion] {
        try modelContext.fetch(
            FetchDescriptor<PendingDeletion>(
                sortBy: [SortDescriptor(\.queuedAt, order: .forward)]
            )
        )
    }

    func state(for identifier: String) throws -> AssetReviewState {
        if let pending = try pending(identifier: identifier) {
            return .pendingDeletion(source: pending.source, queuedAt: pending.queuedAt)
        }
        if let reviewed = try reviewed(identifier: identifier) {
            return .kept(reviewedAt: reviewed.lastReviewedAt)
        }
        return .unreviewed
    }

    func markKept(identifier: String, reviewedAt: Date = .now) throws {
        if let pending = try pending(identifier: identifier) {
            modelContext.delete(pending)
        }

        if let reviewed = try reviewed(identifier: identifier) {
            reviewed.lastReviewedAt = reviewedAt
        } else {
            modelContext.insert(
                ReviewedAsset(assetIdentifier: identifier, lastReviewedAt: reviewedAt)
            )
        }
        try modelContext.save()
    }

    func queueDeletion(
        identifier: String,
        source: PendingDeletionSource,
        queuedAt: Date = .now
    ) throws {
        if let reviewed = try reviewed(identifier: identifier) {
            modelContext.delete(reviewed)
        }

        if let pending = try pending(identifier: identifier) {
            pending.source = source
            pending.queuedAt = queuedAt
        } else {
            modelContext.insert(
                PendingDeletion(
                    assetIdentifier: identifier,
                    source: source,
                    queuedAt: queuedAt
                )
            )
        }
        try modelContext.save()
    }

    func restore(identifier: String, to state: AssetReviewState) throws {
        if let pending = try pending(identifier: identifier) {
            modelContext.delete(pending)
        }
        if let reviewed = try reviewed(identifier: identifier) {
            modelContext.delete(reviewed)
        }

        switch state {
        case .unreviewed:
            break
        case let .kept(reviewedAt):
            modelContext.insert(
                ReviewedAsset(assetIdentifier: identifier, lastReviewedAt: reviewedAt)
            )
        case let .pendingDeletion(source, queuedAt):
            modelContext.insert(
                PendingDeletion(
                    assetIdentifier: identifier,
                    source: source,
                    queuedAt: queuedAt
                )
            )
        }
        try modelContext.save()
    }

    func returnToUnreviewed(identifier: String) throws {
        try restore(identifier: identifier, to: .unreviewed)
    }

    func removeRecords(for identifiers: Set<String>) throws {
        for identifier in identifiers {
            if let pending = try pending(identifier: identifier) {
                modelContext.delete(pending)
            }
            if let reviewed = try reviewed(identifier: identifier) {
                modelContext.delete(reviewed)
            }
            if let classification = try classification(identifier: identifier) {
                modelContext.delete(classification)
            }
        }
        try modelContext.save()
    }

    func discardAllPending() throws {
        for pending in try modelContext.fetch(FetchDescriptor<PendingDeletion>()) {
            modelContext.delete(pending)
        }
        try modelContext.save()
    }

    func resetReviewHistory() throws {
        for reviewed in try modelContext.fetch(FetchDescriptor<ReviewedAsset>()) {
            modelContext.delete(reviewed)
        }
        try modelContext.save()
    }

    func classificationSnapshots() throws -> [String: ClassificationCacheSnapshot] {
        Dictionary(
            uniqueKeysWithValues: try modelContext
                .fetch(FetchDescriptor<AssetClassification>())
                .map { ($0.assetIdentifier, $0.snapshot) }
        )
    }

    func saveClassification(
        identifier: String,
        category: ContentCategory?,
        confidence: Float,
        modificationDate: Date?,
        classifierVersion: Int,
        status: ClassificationRecordStatus,
        attemptedAt: Date = .now
    ) throws {
        if let existing = try classification(identifier: identifier) {
            existing.category = category
            existing.confidence = confidence
            existing.assetModificationDate = modificationDate
            existing.classifierVersion = classifierVersion
            existing.status = status
            existing.lastAttemptAt = attemptedAt
        } else {
            modelContext.insert(
                AssetClassification(
                    assetIdentifier: identifier,
                    category: category,
                    confidence: confidence,
                    assetModificationDate: modificationDate,
                    classifierVersion: classifierVersion,
                    status: status,
                    lastAttemptAt: attemptedAt
                )
            )
        }
        try modelContext.save()
    }

    func removeClassificationRecords(for identifiers: Set<String>) throws {
        for identifier in identifiers {
            if let classification = try classification(identifier: identifier) {
                modelContext.delete(classification)
            }
        }
        try modelContext.save()
    }

    func rebuildClassificationIndex() throws {
        for record in try modelContext.fetch(FetchDescriptor<AssetClassification>()) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    func retryFailedClassifications(identifiers: Set<String>? = nil) throws {
        let records = try modelContext.fetch(FetchDescriptor<AssetClassification>())
        for record in records where record.status == .failed {
            if identifiers == nil || identifiers?.contains(record.assetIdentifier) == true {
                modelContext.delete(record)
            }
        }
        try modelContext.save()
    }

    private func reviewed(identifier: String) throws -> ReviewedAsset? {
        var descriptor = FetchDescriptor<ReviewedAsset>(
            predicate: #Predicate { $0.assetIdentifier == identifier }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func pending(identifier: String) throws -> PendingDeletion? {
        var descriptor = FetchDescriptor<PendingDeletion>(
            predicate: #Predicate { $0.assetIdentifier == identifier }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func classification(identifier: String) throws -> AssetClassification? {
        var descriptor = FetchDescriptor<AssetClassification>(
            predicate: #Predicate { $0.assetIdentifier == identifier }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
