import ImageIO
import UIKit
import UniformTypeIdentifiers

enum GIFTestData {
    @MainActor
    static func make(
        size: CGSize = CGSize(width: 200, height: 100),
        durations: [TimeInterval] = [0.1, 0.25]
    ) throws -> Data {
        let colors: [UIColor] = [.systemIndigo, .systemPink]
        guard durations.count == colors.count else {
            throw GIFTestDataError.invalidConfiguration
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.gif.identifier as CFString,
            colors.count,
            nil
        ) else {
            throw GIFTestDataError.destinationUnavailable
        }

        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ] as [CFString: Any]
        ]
        CGImageDestinationSetProperties(
            destination,
            fileProperties as CFDictionary
        )

        for (color, duration) in zip(colors, durations) {
            let image = UIGraphicsImageRenderer(size: size).image { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            guard let cgImage = image.cgImage else {
                throw GIFTestDataError.frameUnavailable
            }

            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: duration,
                    kCGImagePropertyGIFUnclampedDelayTime: duration
                ] as [CFString: Any]
            ]
            CGImageDestinationAddImage(
                destination,
                cgImage,
                frameProperties as CFDictionary
            )
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GIFTestDataError.finalizationFailed
        }
        return data as Data
    }
}

private enum GIFTestDataError: Error {
    case invalidConfiguration
    case destinationUnavailable
    case frameUnavailable
    case finalizationFailed
}
