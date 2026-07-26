import SwiftUI
import UIKit

struct TextRescueView: View {
    let asset: MediaAssetDescriptor
    let photoLibrary: any PhotoLibraryClient
    let textExtractor: any TextExtractionClient
    let onCompleted: () -> Void
    let onCancel: () -> Void

    @State private var recognizedText = ""
    @State private var isRecognizing = false
    @State private var showingShare = false
    @State private var errorMessage: String?
    @FocusState private var isEditing: Bool

    var body: some View {
        NavigationStack {
            Group {
                if isRecognizing {
                    ProgressView("Finding text…")
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if recognizedText.isEmpty {
                    ContentUnavailableView {
                        Label("No Text Available", systemImage: "text.viewfinder")
                    } description: {
                        Text(errorMessage ?? "No readable text was found in this image.")
                    } actions: {
                        Button("Try Again") {
                            recognize()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Check and edit the text before sending it somewhere safe.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $recognizedText)
                            .focused($isEditing)
                            .font(.body)
                            .padding(8)
                            .background(
                                Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 14)
                            )

                        HStack {
                            Button {
                                UIPasteboard.general.string = recognizedText
                                onCompleted()
                            } label: {
                                Label("Copy & Queue Delete", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                showingShare = true
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Extract Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .task {
                if recognizedText.isEmpty {
                    recognize()
                }
            }
            .sheet(isPresented: $showingShare) {
                ActivityView(items: [recognizedText]) { completed, error in
                    showingShare = false
                    if completed {
                        onCompleted()
                    } else if let error {
                        errorMessage = error
                    }
                }
                .ignoresSafeArea()
            }
        }
        .interactiveDismissDisabled(isRecognizing || showingShare)
    }

    private func recognize() {
        guard !isRecognizing else { return }
        isRecognizing = true
        errorMessage = nil

        Task {
            do {
                let data = try await photoLibrary.recognitionImageData(
                    identifier: asset.id
                )
                recognizedText = try await textExtractor.recognizeText(in: data)
            } catch {
                errorMessage = error.localizedDescription
            }
            isRecognizing = false
        }
    }
}
