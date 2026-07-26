import SwiftUI

struct CategoryPreparationView: View {
    @Environment(\.dismiss) private var dismiss

    let configuration: ReviewConfiguration
    let coordinator: ClassificationCoordinator
    let repository: ReviewRepository
    let photoLibrary: any PhotoLibraryClient
    let onReady: () -> Void
    let onCancel: () -> Void

    @State private var outcome: ClassificationScanOutcome?
    @State private var scanToken = UUID()

    var body: some View {
        NavigationStack {
            Group {
                if let outcome {
                    resultContent(outcome)
                } else {
                    progressContent
                }
            }
            .padding(24)
            .navigationTitle("Finding \(configuration.category.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        coordinator.cancelCurrentWork()
                        dismiss()
                        onCancel()
                    }
                }
            }
        }
        .interactiveDismissDisabled(coordinator.isIndexing)
        .task(id: scanToken) {
            outcome = nil
            let result = await coordinator.prepareCategory(
                configuration: configuration,
                repository: repository,
                photoLibrary: photoLibrary
            )
            if !result.wasCanceled,
               !result.wasPausedBySystem,
               result.failedCount == 0,
               result.errorMessage == nil {
                onReady()
            } else {
                outcome = result
            }
        }
    }

    private var progressContent: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: categorySymbol)
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(.indigo)

            VStack(spacing: 8) {
                Text("Categorizing on this iPhone")
                    .font(.title2.bold())
                Text("Apple Vision examines small previews. Images and category results are never sent to FlickPic.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ProgressView(
                value: Double(coordinator.completedCount),
                total: Double(max(coordinator.totalCount, 1))
            )
            .progressViewStyle(.linear)

            if coordinator.totalCount > 0 {
                Text("\(coordinator.completedCount) of \(coordinator.totalCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func resultContent(_ result: ClassificationScanOutcome) -> some View {
        if result.wasPausedBySystem {
            ContentUnavailableView {
                Label("Categorization Is Paused", systemImage: "pause.circle")
            } description: {
                Text(coordinator.statusDescription)
            } actions: {
                Button("Try Again") {
                    scanToken = UUID()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if result.wasCanceled {
            ContentUnavailableView {
                Label("Categorization Stopped", systemImage: "stop.circle")
            } description: {
                Text("Completed category results were saved. You can continue from where FlickPic stopped.")
            } actions: {
                Button("Continue") {
                    scanToken = UUID()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let errorMessage = result.errorMessage {
            ContentUnavailableView {
                Label(
                    "Couldn’t Finish Categorizing",
                    systemImage: "exclamationmark.triangle"
                )
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") {
                    scanToken = UUID()
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label(
                    "Some Items Couldn’t Be Analyzed",
                    systemImage: "photo.badge.exclamationmark"
                )
            } description: {
                Text("\(result.failedCount) items were left uncategorized. They will not be included in Other Photos.")
            } actions: {
                Button("Retry Failed Items") {
                    do {
                        try coordinator.retryFailed(repository: repository)
                        scanToken = UUID()
                    } catch {
                        coordinator.cancelCurrentWork()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Review Available Matches") {
                    onReady()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var categorySymbol: String {
        switch configuration.category {
        case .receipts: "receipt"
        case .documents: "doc.text.viewfinder"
        case .otherPhotos: "photo.on.rectangle"
        case .any, .screenshots: "photo.stack"
        }
    }
}
