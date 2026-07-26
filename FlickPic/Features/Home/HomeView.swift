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
    @State private var dashboard = CategoryDashboardModel()
    @State private var dashboardRefreshToken = UUID()
    @State private var errorMessage: String?

    private var preference: AppPreference? {
        preferences.first(where: { $0.key == "primary" })
    }

    private var configuration: ReviewConfiguration {
        preference?.configuration ?? ReviewConfiguration()
    }

    private var hasStartedCategorization: Bool {
        preference?.hasStartedCategorization == true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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
                }
                .padding(24)
            }
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
                    do {
                        try ReviewRepository(modelContext: modelContext)
                            .saveConfiguration(newConfiguration)
                        dashboardRefreshToken = UUID()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    showingSetup = false
                }
            }
            .sheet(isPresented: $showingQueue) {
                NavigationStack {
                    PendingDeletionView(
                        photoLibrary: photoLibrary,
                        classificationCoordinator: classificationCoordinator
                    )
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
            .fullScreenCover(
                item: $activeSession,
                onDismiss: {
                    classificationCoordinator.setReviewActive(false)
                    dashboardRefreshToken = UUID()
                }
            ) { session in
                ReviewSessionView(
                    model: session,
                    photoLibrary: photoLibrary,
                    classificationCoordinator: classificationCoordinator
                ) {
                    session.endSession()
                    activeSession = nil
                }
            }
            .task(id: dashboardRefreshToken) {
                guard photoLibrary.authorizationState.canReadLibrary else { return }
                await dashboard.load(
                    configuration: configuration,
                    repository: ReviewRepository(modelContext: modelContext),
                    photoLibrary: photoLibrary,
                    coordinator: classificationCoordinator
                )
            }
            .onChange(of: photoLibrary.changeVersion) {
                dashboardRefreshToken = UUID()
            }
            .onChange(of: photoLibrary.authorizationState) {
                dashboardRefreshToken = UUID()
            }
            .alert(
                "Something Went Wrong",
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
    }

    @ViewBuilder
    private var authorizationContent: some View {
        switch photoLibrary.authorizationState {
        case .full, .limited:
            VStack(alignment: .leading, spacing: 18) {
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

                reviewActions
                categoryDashboard
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

    private var reviewActions: some View {
        VStack(spacing: 14) {
            Button {
                launchSession(
                    request: ReviewRequest(configuration: configuration)
                )
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
    }

    @ViewBuilder
    private var categoryDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review by Category")
                .font(.title2.bold())

            if dashboard.isLoading, dashboard.metadataBuckets.isEmpty {
                ProgressView("Loading library details…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let dashboardError = dashboard.errorMessage {
                Label(dashboardError, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                bucketGrid(dashboard.metadataBuckets)
            }

            Divider()

            if hasStartedCategorization {
                categorizationStatus

                if dashboard.visionBuckets.isEmpty {
                    Text(
                        classificationCoordinator.isIndexing
                            ? "Vision categories will appear here as they’re found."
                            : "No Vision categories match this review setup yet."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    bucketGrid(dashboard.visionBuckets)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Discover more categories", systemImage: "sparkles")
                        .font(.headline)
                    Text(
                        "Apple Vision can privately find categories such as pets, food, places, and documents. Results stay on this iPhone."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Button("Start Categorizing") {
                        startCategorization()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("start-categorizing")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.indigo.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 16)
                )
            }
        }
    }

    private var categorizationStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    classificationCoordinator.statusDescription,
                    systemImage: classificationCoordinator.isIndexing
                        ? "sparkles"
                        : "checkmark.circle"
                )
                .font(.headline)
                Spacer()
                Text("\(dashboard.visionCategoryCount) found")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if classificationCoordinator.isIndexing {
                ProgressView(
                    value: Double(classificationCoordinator.completedCount),
                    total: Double(max(classificationCoordinator.totalCount, 1))
                )
                .progressViewStyle(.linear)

                Text(
                    "\(classificationCoordinator.completedCount) of \(classificationCoordinator.totalCount) images analyzed"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            if classificationCoordinator.deferredCloudCount > 0 {
                Text(
                    "\(classificationCoordinator.deferredCloudCount) items are waiting for an iCloud background retry."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func bucketGrid(_ buckets: [CategoryBucket]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(buckets) { bucket in
                Button {
                    launchSession(
                        request: ReviewRequest(
                            configuration: configuration,
                            category: bucket.category
                        )
                    )
                } label: {
                    CategoryBucketCard(
                        bucket: bucket,
                        photoLibrary: photoLibrary
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("category-\(bucket.category.id)")
            }
        }
    }

    private func startCategorization() {
        do {
            let repository = ReviewRepository(modelContext: modelContext)
            try repository.startCategorization()
            classificationCoordinator.startAutomaticIndexing(
                repository: repository,
                photoLibrary: photoLibrary
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func launchSession(request: ReviewRequest) {
        let repository = ReviewRepository(modelContext: modelContext)
        classificationCoordinator.setReviewActive(true)
        activeSession = ReviewSessionModel(
            request: request,
            repository: repository,
            photoLibrary: photoLibrary,
            classificationCoordinator: classificationCoordinator,
            hapticsEnabled: preference?.hapticsEnabled ?? true
        )
    }
}

private struct CategoryBucketCard: View {
    let bucket: CategoryBucket
    let photoLibrary: PhotoLibraryService

    @State private var thumbnail: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .overlay {
                                Image(systemName: bucket.category.systemImage)
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(bucket.category.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(bucket.count) items")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(.white)
                .padding(10)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .bottomLeading
            )
        }
        .frame(height: 126)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .task(id: bucket.representativeAsset.id) {
            thumbnail = try? await photoLibrary.thumbnail(
                identifier: bucket.representativeAsset.id,
                targetSize: CGSize(width: 360, height: 260)
            )
        }
    }
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
