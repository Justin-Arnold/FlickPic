import SwiftData
import SwiftUI

struct PendingDeletionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PendingDeletion.queuedAt) private var pendingItems: [PendingDeletion]

    let photoLibrary: PhotoLibraryService
    let classificationCoordinator: ClassificationCoordinator

    @State private var descriptors: [MediaAssetDescriptor] = []
    @State private var selectedAsset: MediaAssetDescriptor?
    @State private var showingDeleteConfirmation = false
    @State private var showingDiscardConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 105), spacing: 3)
    ]

    private var descriptorsByIdentifier: [String: MediaAssetDescriptor] {
        Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
    }

    private var unavailableCount: Int {
        max(pendingItems.count - descriptors.count, 0)
    }

    var body: some View {
        Group {
            if pendingItems.isEmpty {
                ContentUnavailableView {
                    Label("Deletion Queue Is Empty", systemImage: "trash")
                } description: {
                    Text("Items you swipe left will wait here for your confirmation.")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(pendingItems) { item in
                            if let asset = descriptorsByIdentifier[item.assetIdentifier] {
                                Button {
                                    selectedAsset = asset
                                } label: {
                                    PendingQueueCell(
                                        asset: asset,
                                        photoLibrary: photoLibrary
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(queueCellLabel(asset))
                            } else {
                                UnavailablePendingQueueCell(
                                    canManageSelection:
                                        photoLibrary.authorizationState == .limited
                                ) {
                                    photoLibrary.presentLimitedLibraryPicker()
                                }
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 10) {
                        if unavailableCount > 0 {
                            Text(
                                "\(unavailableCount) queued \(unavailableCount == 1 ? "item is" : "items are") not currently available to FlickPic."
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        }

                        Button {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                if isDeleting {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Label(
                                    "Delete \(descriptors.count) Items",
                                    systemImage: "trash"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)
                        .disabled(isDeleting || descriptors.isEmpty)
                    }
                    .padding()
                    .background(.bar)
                }
            }
        }
        .navigationTitle("Pending Deletions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            if !pendingItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Discard Queue", role: .destructive) {
                            showingDiscardConfirmation = true
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .task(
            id: PendingQueueLoadID(
                identifiers: pendingItems.map(\.assetIdentifier),
                libraryChangeVersion: photoLibrary.changeVersion,
                authorizationState: photoLibrary.authorizationState.rawValue
            )
        ) {
            await loadDescriptorsAndReconcile()
        }
        .sheet(item: $selectedAsset) { asset in
            PendingAssetDetailView(
                asset: asset,
                photoLibrary: photoLibrary,
                onKeep: {
                    do {
                        try ReviewRepository(modelContext: modelContext)
                            .markKept(identifier: asset.id)
                        selectedAsset = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                },
                onReturnToUnreviewed: {
                    do {
                        try ReviewRepository(modelContext: modelContext)
                            .returnToUnreviewed(identifier: asset.id)
                        selectedAsset = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            )
        }
        .alert("Delete these items?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", role: .destructive) {
                deletePendingItems()
            }
        } message: {
            Text("Photos will show its own confirmation next. If you cancel there, this queue will stay unchanged.")
        }
        .alert("Discard the queue?", isPresented: $showingDiscardConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) {
                do {
                    try ReviewRepository(modelContext: modelContext).discardAllPending()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("These items will return to Unreviewed. Nothing will be deleted from Photos.")
        }
        .alert(
            "Couldn’t Update the Queue",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadDescriptorsAndReconcile() async {
        let identifiers = pendingItems.map(\.assetIdentifier)
        let loaded = await photoLibrary.descriptors(for: identifiers)
        let available = Set(loaded.map(\.id))
        let missing = PendingQueueReconciliation.identifiersToRemove(
            pendingIdentifiers: Set(identifiers),
            availableIdentifiers: available,
            authorizationState: photoLibrary.authorizationState
        )

        if !missing.isEmpty {
            try? ReviewRepository(modelContext: modelContext)
                .removeRecords(for: missing)
        }
        descriptors = loaded
    }

    private func deletePendingItems() {
        let identifiers = pendingItems.map(\.assetIdentifier)
        guard !identifiers.isEmpty else { return }
        isDeleting = true

        Task {
            await classificationCoordinator.suspendForPhotoLibraryChange()
            defer {
                classificationCoordinator.resumeAfterPhotoLibraryChange()
            }

            do {
                let deleted = try await photoLibrary.deleteAssets(
                    identifiers: identifiers
                )
                guard !deleted.isEmpty else {
                    throw PhotoLibraryError.assetUnavailable
                }
                try ReviewRepository(modelContext: modelContext)
                    .removeRecords(for: deleted)
            } catch {
                errorMessage = error.localizedDescription
            }
            isDeleting = false
        }
    }

    private func queueCellLabel(_ asset: MediaAssetDescriptor) -> String {
        var parts = [asset.mediaKind.title]
        if asset.isScreenshot { parts.append("screenshot") }
        if let date = asset.creationDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: ", ")
    }
}

enum PendingQueueReconciliation {
    static func identifiersToRemove(
        pendingIdentifiers: Set<String>,
        availableIdentifiers: Set<String>,
        authorizationState: AuthorizationState
    ) -> Set<String> {
        guard authorizationState == .full else { return [] }
        return pendingIdentifiers.subtracting(availableIdentifiers)
    }
}

private struct PendingQueueLoadID: Equatable {
    let identifiers: [String]
    let libraryChangeVersion: Int
    let authorizationState: String
}

private struct UnavailablePendingQueueCell: View {
    let canManageSelection: Bool
    let onManageSelection: () -> Void

    var body: some View {
        Group {
            if canManageSelection {
                Button(action: onManageSelection) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityLabel("Queued item is not currently accessible")
    }

    private var content: some View {
        Rectangle()
            .fill(Color(uiColor: .secondarySystemBackground))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title2)
                    Text(canManageSelection ? "Manage Access" : "Unavailable")
                        .font(.caption2.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(8)
            }
    }
}

private struct PendingQueueCell: View {
    let asset: MediaAssetDescriptor
    let photoLibrary: any PhotoLibraryClient

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color(uiColor: .secondarySystemBackground))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ProgressView()
                    }
                }
                .clipped()

            if asset.mediaKind == .video {
                Label(
                    asset.duration.queueFormattedDuration,
                    systemImage: "video.fill"
                )
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(5)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(5)
            }
        }
        .task(id: asset.id) {
            image = try? await photoLibrary.thumbnail(
                identifier: asset.id,
                targetSize: CGSize(width: 360, height: 360)
            )
        }
    }
}

private struct PendingAssetDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let asset: MediaAssetDescriptor
    let photoLibrary: any PhotoLibraryClient
    let onKeep: () -> Void
    let onReturnToUnreviewed: () -> Void

    var body: some View {
        NavigationStack {
            MediaCardView(
                asset: asset,
                photoLibrary: photoLibrary,
                onLater: {}
            )
            .padding()
            .background(Color.black)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        onReturnToUnreviewed()
                    } label: {
                        Label("Review Later", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onKeep()
                    } label: {
                        Label("Keep", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Pending Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension TimeInterval {
    var queueFormattedDuration: String {
        let totalSeconds = max(Int(self.rounded()), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
