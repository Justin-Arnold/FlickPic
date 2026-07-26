import CoreGraphics

nonisolated enum ReviewCardGestureAction: CaseIterable, Hashable {
    case queueDelete
    case keep
    case rescue
}

nonisolated enum ReviewCardGesturePolicy {
    static let minimumDistance: CGFloat = 12
    static let overlayThreshold: CGFloat = 20
    static let activationThreshold: CGFloat = 110
    static let fullOverlayDistance: CGFloat = 160

    static func constrainedOffset(
        for translation: CGSize
    ) -> CGSize? {
        if abs(translation.width) > abs(translation.height) {
            return CGSize(width: translation.width, height: 0)
        }
        if translation.height < 0 {
            return CGSize(width: 0, height: translation.height)
        }
        return nil
    }

    static func action(
        for offset: CGSize
    ) -> ReviewCardGestureAction? {
        if offset.width <= -activationThreshold {
            return .queueDelete
        }
        if offset.width >= activationThreshold {
            return .keep
        }
        if offset.height <= -activationThreshold {
            return .rescue
        }
        return nil
    }
}
