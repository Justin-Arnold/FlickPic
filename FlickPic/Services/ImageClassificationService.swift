@preconcurrency import Vision
import Foundation

protocol ImageClassificationClient: Sendable {
    var classifierVersion: Int { get }
    func classify(imageData: Data) async throws -> ImageClassificationResult
}

struct VisionImageClassificationService: ImageClassificationClient {
    let classifierVersion = ImageClassificationPolicy.classifierVersion

    func classify(imageData: Data) async throws -> ImageClassificationResult {
        var request = ClassifyImageRequest(.revision2)
        request.cropAndScaleAction = .scaleToFit
        let observations = try await request.perform(on: imageData)

        let candidates: [ClassificationCandidate] = observations.compactMap {
            (observation: ClassificationObservation) -> ClassificationCandidate? in
            guard observation.identifier == "receipt"
                    || observation.identifier == "document" else {
                return nil
            }

            let meetsHighPrecision = observation.hasPrecisionRecallCurve
                ? observation.hasMinimumRecall(0.01, forPrecision: 0.90)
                : observation.confidence >= 0.90

            return ClassificationCandidate(
                identifier: observation.identifier,
                confidence: observation.confidence,
                meetsHighPrecision: meetsHighPrecision
            )
        }

        return ImageClassificationPolicy.resolve(
            candidates: candidates,
            classifierVersion: classifierVersion
        )
    }
}

struct ClassificationCandidate: Equatable, Sendable {
    let identifier: String
    let confidence: Float
    let meetsHighPrecision: Bool
}

enum ImageClassificationPolicy {
    static let classifierVersion = 1

    static func resolve(
        candidates: [ClassificationCandidate],
        classifierVersion: Int
    ) -> ImageClassificationResult {
        if let receipt = candidates.first(where: {
            $0.identifier == "receipt" && $0.meetsHighPrecision
        }) {
            return ImageClassificationResult(
                category: .receipt,
                confidence: receipt.confidence,
                classifierVersion: classifierVersion
            )
        }

        if let document = candidates.first(where: {
            $0.identifier == "document" && $0.meetsHighPrecision
        }) {
            return ImageClassificationResult(
                category: .document,
                confidence: document.confidence,
                classifierVersion: classifierVersion
            )
        }

        let strongestRelevantConfidence = candidates
            .map(\.confidence)
            .max() ?? 0
        return ImageClassificationResult(
            category: .otherPhoto,
            confidence: max(0, 1 - strongestRelevantConfidence),
            classifierVersion: classifierVersion
        )
    }
}
