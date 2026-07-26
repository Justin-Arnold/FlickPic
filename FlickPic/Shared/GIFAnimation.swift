import Foundation
@preconcurrency import ImageIO
import QuartzCore
import SwiftUI
import UIKit

struct GIFAnimation: @unchecked Sendable, Identifiable {
    let id: UUID
    let frames: [CGImage]
    let frameDurations: [TimeInterval]

    nonisolated init(
        id: UUID = UUID(),
        frames: [CGImage],
        frameDurations: [TimeInterval]
    ) {
        self.id = id
        self.frames = frames
        self.frameDurations = frameDurations
    }

    nonisolated var frameCount: Int {
        frames.count
    }

    nonisolated var totalDuration: TimeInterval {
        max(frameDurations.reduce(0, +), 0.02)
    }

    nonisolated var frameStartTimes: [NSNumber] {
        var elapsed: TimeInterval = 0
        let total = totalDuration
        return frameDurations.map { frameDuration in
            defer { elapsed += frameDuration }
            return NSNumber(value: elapsed / total)
        }
    }

    var posterImage: UIImage {
        UIImage(cgImage: frames[0])
    }
}

enum GIFAnimationError: LocalizedError, Equatable {
    case invalidData
    case frameUnavailable

    var errorDescription: String? {
        "FlickPic could not play this animated GIF."
    }
}

enum GIFAnimationDecoder {
    nonisolated static let defaultMemoryBudget = 64 * 1_024 * 1_024

    nonisolated static func decode(
        data: Data,
        maximumPixelDimension: CGFloat,
        memoryBudget: Int = defaultMemoryBudget
    ) async throws -> GIFAnimation {
        let decodingTask = Task.detached(priority: .userInitiated) {
            try decodeSynchronously(
                data: data,
                maximumPixelDimension: maximumPixelDimension,
                memoryBudget: memoryBudget
            )
        }

        return try await withTaskCancellationHandler {
            try await decodingTask.value
        } onCancel: {
            decodingTask.cancel()
        }
    }

    private nonisolated static func decodeSynchronously(
        data: Data,
        maximumPixelDimension: CGFloat,
        memoryBudget: Int
    ) throws -> GIFAnimation {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            nil
        ) else {
            throw GIFAnimationError.invalidData
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw GIFAnimationError.invalidData
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any]
        let sourceWidth = (
            properties?[kCGImagePropertyPixelWidth] as? NSNumber
        )?.doubleValue ?? 1
        let sourceHeight = (
            properties?[kCGImagePropertyPixelHeight] as? NSNumber
        )?.doubleValue ?? 1
        let sourceMaximumDimension = max(sourceWidth, sourceHeight, 1)
        let sourcePixelCount = max(sourceWidth * sourceHeight, 1)

        let requestedScale = min(
            1,
            max(Double(maximumPixelDimension), 1) / sourceMaximumDimension
        )
        let budgetedPixelsPerFrame = max(
            Double(max(memoryBudget, 1)) / Double(frameCount * 4),
            1
        )
        let budgetScale = min(
            1,
            sqrt(budgetedPixelsPerFrame / sourcePixelCount)
        )
        let decodeMaximumDimension = max(
            1,
            Int(floor(sourceMaximumDimension * min(requestedScale, budgetScale)))
        )

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: decodeMaximumDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]

        var frames: [CGImage] = []
        var durations: [TimeInterval] = []
        frames.reserveCapacity(frameCount)
        durations.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            try Task.checkCancellation()
            guard let frame = CGImageSourceCreateThumbnailAtIndex(
                source,
                index,
                thumbnailOptions as CFDictionary
            ) else {
                throw GIFAnimationError.frameUnavailable
            }
            frames.append(frame)
            durations.append(frameDuration(source: source, index: index))
        }

        return GIFAnimation(
            frames: frames,
            frameDurations: durations
        )
    }

    private nonisolated static func frameDuration(
        source: CGImageSource,
        index: Int
    ) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            index,
            nil
        ) as? [CFString: Any],
              let gifProperties = properties[
                kCGImagePropertyGIFDictionary
              ] as? [CFString: Any] else {
            return 0.1
        }

        let unclamped = (
            gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber
        )?.doubleValue
        let clamped = (
            gifProperties[kCGImagePropertyGIFDelayTime] as? NSNumber
        )?.doubleValue
        let duration = unclamped ?? clamped ?? 0.1
        return duration > 0 ? max(duration, 0.02) : 0.1
    }
}

struct GIFPlaybackView: UIViewRepresentable {
    let animation: GIFAnimation

    func makeUIView(context: Context) -> GIFLayerView {
        let view = GIFLayerView()
        view.setAnimation(animation)
        return view
    }

    func updateUIView(_ view: GIFLayerView, context: Context) {
        view.setAnimation(animation)
    }

    static func dismantleUIView(
        _ view: GIFLayerView,
        coordinator: Void
    ) {
        view.stopAnimating()
    }
}

@MainActor
final class GIFLayerView: UIView {
    private var animationID: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.contentsGravity = .resizeAspect
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAnimation(_ animation: GIFAnimation) {
        guard animationID != animation.id else { return }
        animationID = animation.id
        GIFLayerAnimator.apply(animation, to: layer)
    }

    func stopAnimating() {
        animationID = nil
        GIFLayerAnimator.remove(from: layer)
    }
}

@MainActor
enum GIFLayerAnimator {
    private static let animationKey = "FlickPicGIFPlayback"

    static func apply(_ animation: GIFAnimation, to layer: CALayer) {
        layer.removeAnimation(forKey: animationKey)
        layer.contents = animation.frames.first

        guard animation.frameCount > 1 else { return }

        let playback = CAKeyframeAnimation(keyPath: "contents")
        playback.values = animation.frames.map { $0 as Any }
        playback.keyTimes = animation.frameStartTimes
        playback.duration = animation.totalDuration
        playback.calculationMode = .discrete
        playback.repeatCount = .infinity
        playback.isRemovedOnCompletion = false
        layer.add(playback, forKey: animationKey)
    }

    static func remove(from layer: CALayer) {
        layer.removeAnimation(forKey: animationKey)
    }
}
