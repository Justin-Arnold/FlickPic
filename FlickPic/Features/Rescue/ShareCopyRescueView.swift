import SwiftUI

struct ShareCopyRescueView: View {
    let asset: MediaAssetDescriptor
    let photoLibrary: any PhotoLibraryClient
    let onCompleted: () -> Void
    let onCancel: () -> Void

    @State private var export: PreparedMediaExport?
    @State private var isPreparing = false
    @State private var showingActivity = false
    @State private var errorMessage: String?
    @State private var preparationToken = UUID()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                if isPreparing {
                    ProgressView("Preparing a copy…")
                        .controlSize(.large)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn’t Prepare Copy", systemImage: "square.and.arrow.up.trianglebadge.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") {
                            preparationToken = UUID()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Image(systemName: asset.mediaKind == .video ? "video" : "photo")
                        .font(.system(size: 58))
                        .foregroundStyle(.indigo)
                    Text("Share a copy")
                        .font(.title2.bold())
                    Text("After the share completes, this item will be added to your deletion queue. You will still review that queue before anything is deleted.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if export != nil {
                        Button("Share Copy") {
                            showingActivity = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Rescue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cleanExport()
                        onCancel()
                    }
                }
            }
            .task(id: preparationToken) {
                await prepareExport()
            }
            .sheet(isPresented: $showingActivity) {
                if let export {
                    ActivityView(items: export.itemURLs) { completed, error in
                        showingActivity = false
                        if completed {
                            cleanExport()
                            onCompleted()
                        } else if let error {
                            cleanExport()
                            errorMessage = error
                        }
                    }
                    .ignoresSafeArea()
                }
            }
        }
        .interactiveDismissDisabled(isPreparing || showingActivity)
        .onDisappear {
            cleanExport()
        }
    }

    private func prepareExport() async {
        guard !isPreparing else { return }
        cleanExport()
        isPreparing = true
        errorMessage = nil

        do {
            let prepared = try await photoLibrary.exportCurrentMedia(
                identifier: asset.id
            )
            guard !Task.isCancelled else {
                photoLibrary.discardExport(prepared)
                isPreparing = false
                return
            }
            export = prepared
            showingActivity = true
        } catch is CancellationError {
            // The export service removes partial files before propagating cancellation.
        } catch {
            errorMessage = error.localizedDescription
        }
        isPreparing = false
    }

    private func cleanExport() {
        guard let export else { return }
        self.export = nil
        photoLibrary.discardExport(export)
    }
}
