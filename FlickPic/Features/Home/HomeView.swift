import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PendingDeletion.queuedAt) private var pendingItems: [PendingDeletion]
    @Query private var preferences: [AppPreference]

    let photoLibrary: PhotoLibraryService
    let classificationCoordinator: ClassificationCoordinator

    @State private var showingSetup = false
    @State private var showingQueue = false
    @State private var showingSettings = false
    @State private var activeSession: ReviewSessionModel?
    @State private var categoryPreparation: CategoryPreparationRequest?

    private var preference: AppPreference? {
        preferences.first(where: { $0.key == "primary" })
    }

    private var configuration: ReviewConfiguration {
        preference?.configuration ?? ReviewConfiguration()
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.indigo)
                        .accessibilityHidden(true)
                    Text("FlickPic")
                        .font(.largeTitle.bold())
                    Text("Keep what matters. Queue the rest.")
                        .foregroundStyle(.secondary)
                }

                authorizationContent

                Spacer()
            }
            .padding(24)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        showingSettings = true
                    }
                }
            }
            .sheet(isPresented: $showingSetup) {
                SessionSetupView(configuration: configuration) { newConfiguration in
                    try? ReviewRepository(modelContext: modelContext)
                        .saveConfiguration(newConfiguration)
                    showingSetup = false
                }
            }
            .sheet(isPresented: $showingQueue) {
                NavigationStack {
                    PendingDeletionView(photoLibrary: photoLibrary)
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView(
                        photoLibrary: photoLibrary,
                        classificationCoordinator: classificationCoordinator
                    )
                }
            }
            .sheet(item: $categoryPreparation) { request in
                CategoryPreparationView(
                    configuration: request.configuration,
                    coordinator: classificationCoordinator,
                    repository: ReviewRepository(modelContext: modelContext),
                    photoLibrary: photoLibrary
                ) {
                    categoryPreparation = nil
                    Task { @MainActor in
                        await Task.yield()
                        launchSession(configuration: request.configuration)
                    }
                } onCancel: {
                    categoryPreparation = nil
                    Task { @MainActor in
                        await Task.yield()
                        showingSetup = true
                    }
                }
            }
            .fullScreenCover(item: $activeSession) { session in
                ReviewSessionView(
                    model: session,
                    photoLibrary: photoLibrary
                ) {
                    session.endSession()
                    activeSession = nil
                    classificationCoordinator.setReviewActive(false)
                }
            }
        }
    }

    @ViewBuilder
    private var authorizationContent: some View {
        switch photoLibrary.authorizationState {
        case .full, .limited:
            VStack(spacing: 14) {
                if photoLibrary.authorizationState == .limited {
                    Label(
                        "Only your selected Photos items are available.",
                        systemImage: "photo.badge.checkmark"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    startSession()
                } label: {
                    Label("Start Reviewing", systemImage: "hand.draw")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("start-reviewing")

                Button {
                    showingSetup = true
                } label: {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(configuration.summary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Review setup, \(configuration.summary)")
                .accessibilityIdentifier("review-setup")

                if !pendingItems.isEmpty {
                    Button {
                        showingQueue = true
                    } label: {
                        HStack {
                            Label("Pending Deletions", systemImage: "trash")
                            Spacer()
                            Text("\(pendingItems.count)")
                                .font(.headline.monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.large)
                    .accessibilityIdentifier("pending-deletions")
                }
            }

        case .notDetermined:
            PermissionCard(
                title: "Photos access is needed",
                detail: "Choose which photos and videos FlickPic can help you review.",
                buttonTitle: "Continue"
            ) {
                Task { _ = await photoLibrary.requestAuthorization() }
            }

        case .denied, .restricted:
            PermissionCard(
                title: "Photos access is off",
                detail: "Enable read and write access in Settings to review your library.",
                buttonTitle: "Open Settings"
            ) {
                photoLibrary.openSystemSettings()
            }
        }
    }

    private func startSession() {
        if configuration.category.requiresClassificationIndex {
            categoryPreparation = CategoryPreparationRequest(
                configuration: configuration
            )
        } else {
            launchSession(configuration: configuration)
        }
    }

    private func launchSession(configuration: ReviewConfiguration) {
        let repository = ReviewRepository(modelContext: modelContext)
        classificationCoordinator.setReviewActive(true)
        activeSession = ReviewSessionModel(
            configuration: configuration,
            repository: repository,
            photoLibrary: photoLibrary,
            hapticsEnabled: preference?.hapticsEnabled ?? true
        )
    }
}

private struct CategoryPreparationRequest: Identifiable {
    let id = UUID()
    let configuration: ReviewConfiguration
}

private struct PermissionCard: View {
    let title: String
    let detail: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.bold())
            Text(detail)
                .foregroundStyle(.secondary)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
