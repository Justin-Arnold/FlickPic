@preconcurrency import Vision
import Foundation

protocol TextExtractionClient: Sendable {
    func recognizeText(in imageData: Data) async throws -> String
}

struct TextExtractionService: TextExtractionClient {
    func recognizeText(in imageData: Data) async throws -> String {
        let text = try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(data: imageData)
            try handler.perform([request])

            let observations = request.results ?? []
            return observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.value

        guard !text.isEmpty else {
            throw PhotoLibraryError.noRecognizedText
        }
        return text
    }
}
