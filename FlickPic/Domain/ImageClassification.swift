import Foundation

enum ContentCategory: String, Codable, CaseIterable, Sendable {
    case screenshot
    case receipt
    case document
    case otherPhoto

    var title: String {
        switch self {
        case .screenshot: "Screenshot"
        case .receipt: "Receipt"
        case .document: "Document"
        case .otherPhoto: "Other Photo"
        }
    }
}

enum ContentCategoryFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case any
    case screenshots
    case receipts
    case documents
    case otherPhotos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "Any"
        case .screenshots: "Screenshots"
        case .receipts: "Receipts"
        case .documents: "Documents"
        case .otherPhotos: "Other Photos"
        }
    }

    var requiresClassificationIndex: Bool {
        switch self {
        case .receipts, .documents, .otherPhotos:
            true
        case .any, .screenshots:
            false
        }
    }

    var storedCategory: ContentCategory? {
        switch self {
        case .any: nil
        case .screenshots: .screenshot
        case .receipts: .receipt
        case .documents: .document
        case .otherPhotos: .otherPhoto
        }
    }
}

enum ClassificationRecordStatus: String, Codable, Sendable {
    case classified
    case deferredCloud
    case failed
}

struct ImageClassificationResult: Equatable, Sendable {
    let category: ContentCategory
    let confidence: Float
    let classifierVersion: Int
}

struct ClassificationCacheSnapshot: Equatable, Sendable {
    let assetIdentifier: String
    let category: ContentCategory?
    let confidence: Float
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
