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

        let candidates: [ClassificationCandidate] = observations.map {
            (observation: ClassificationObservation) in
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
    static let classifierVersion = 2
    static let maximumTagsPerAsset = 5

    static func resolve(
        candidates: [ClassificationCandidate],
        classifierVersion: Int
    ) -> ImageClassificationResult {
        var strongestCandidates: [String: ClassificationCandidate] = [:]
        for candidate in candidates where candidate.meetsHighPrecision {
            if let existing = strongestCandidates[candidate.identifier],
               existing.confidence >= candidate.confidence {
                continue
            }
            strongestCandidates[candidate.identifier] = candidate
        }

        let tags = strongestCandidates.values
            .sorted {
                if $0.confidence != $1.confidence {
                    return $0.confidence > $1.confidence
                }
                return $0.identifier < $1.identifier
            }
            .prefix(maximumTagsPerAsset)
            .map {
                VisionTag(
                    identifier: $0.identifier,
                    confidence: $0.confidence
                )
            }
        return ImageClassificationResult(
            tags: tags,
            classifierVersion: classifierVersion
        )
    }
}
