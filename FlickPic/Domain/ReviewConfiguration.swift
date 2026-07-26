import Foundation

enum ReviewScopeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case unreviewed
    case screenshots
    case recent
    case custom

    static var allCases: [ReviewScopeKind] {
        [.unreviewed, .recent, .custom]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unreviewed: "Unreviewed"
        case .screenshots: "Screenshots"
        case .recent: "Recent"
        case .custom: "Custom Range"
        }
    }
}

enum MediaFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case photos
    case videos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Media"
        case .photos: "Photos"
        case .videos: "Videos"
        }
    }
}

enum ReviewOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case oldestFirst
    case newestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oldestFirst: "Oldest First"
        case .newestFirst: "Newest First"
        }
    }
}

struct ReviewConfiguration: Equatable, Sendable {
    var scope: ReviewScopeKind = .unreviewed
    var recentDays = 14
    var customStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    var customEnd = Date.now
    var mediaFilter: MediaFilter = .all
    var category: ContentCategoryFilter = .any
    var order: ReviewOrder = .oldestFirst
    var includeReviewed = false
    var includeFavorites = false

    var summary: String {
        "\(scopeSummary) · \(contentSummary) · \(order.title)"
    }

    var scopeSummary: String {
        switch scope {
        case .recent:
            "Last \(recentDays) Days"
        default:
            scope.title
        }
    }

    nonisolated var effectiveMediaFilter: MediaFilter {
        category == .any ? mediaFilter : .photos
    }

    var contentSummary: String {
        category == .any ? effectiveMediaFilter.title : category.title
    }

    nonisolated var normalizedDateRange: ClosedRange<Date>? {
        let calendar = Calendar.autoupdatingCurrent

        switch scope {
        case .unreviewed, .screenshots:
            return nil
        case .recent:
            let startOfToday = calendar.startOfDay(for: .now)
            let start = calendar.date(byAdding: .day, value: -(recentDays - 1), to: startOfToday) ?? startOfToday
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfToday) ?? .now
            return start...end
        case .custom:
            let earlier = min(customStart, customEnd)
            let later = max(customStart, customEnd)
            let start = calendar.startOfDay(for: earlier)
            let laterStart = calendar.startOfDay(for: later)
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: laterStart) ?? later
            return start...end
        }
    }

    func matchesCategory(
        asset: MediaAssetDescriptor,
        indexedCategory: ContentCategory?
    ) -> Bool {
        switch category {
        case .any:
            return true
        case .screenshots:
            return asset.isScreenshot
        case .receipts, .documents, .otherPhotos:
            guard !asset.isScreenshot else { return false }
            return indexedCategory == category.storedCategory
        }
    }
}
