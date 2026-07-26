import Foundation
@testable import FlickPic

actor ClassificationProbe {
    private(set) var identifiers: [String] = []
    private(set) var maximumConcurrentCalls = 0
    private var activeCalls = 0

    func begin(identifier: String) {
        identifiers.append(identifier)
        activeCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, activeCalls)
    }

    func end() {
        activeCalls -= 1
    }
}

struct FakeImageClassificationClient: ImageClassificationClient {
    let classifierVersion: Int
    let results: [String: ImageClassificationResult]
    let failingIdentifiers: Set<String>
    let delay: Duration
    let probe: ClassificationProbe

    init(
        classifierVersion: Int = 1,
        results: [String: ImageClassificationResult] = [:],
        failingIdentifiers: Set<String> = [],
        delay: Duration = .zero,
        probe: ClassificationProbe = ClassificationProbe()
    ) {
        self.classifierVersion = classifierVersion
        self.results = results
        self.failingIdentifiers = failingIdentifiers
        self.delay = delay
        self.probe = probe
    }

    func classify(imageData: Data) async throws -> ImageClassificationResult {
        let identifier = String(decoding: imageData, as: UTF8.self)
        await probe.begin(identifier: identifier)

        do {
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
            try Task.checkCancellation()
            if failingIdentifiers.contains(identifier) {
                throw FakeClassificationError.failed
            }
            let result = results[identifier] ?? ImageClassificationResult(
                category: .otherPhoto,
                confidence: 1,
                classifierVersion: classifierVersion
            )
            await probe.end()
            return result
        } catch {
            await probe.end()
            throw error
        }
    }
}

private enum FakeClassificationError: Error {
    case failed
}
