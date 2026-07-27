import SwiftData
import SwiftUI

enum MainTab: Hashable {
    case review
    case categories
    case queue
    case settings

    var accessibilityIdentifier: String {
        switch self {
        case .review: "tab-review"
        case .categories: "tab-categories"
        case .queue: "tab-queue"
        case .settings: "tab-settings"
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PendingDeletion.queuedAt)
    private var pendingItems: [PendingDeletion]
    @Query private var preferences: [AppPreference]

    let photoLibrary: PhotoLibraryService
    let classificationCoordinator: ClassificationCoordinator

    @State private var selectedTab: MainTab = .review
    @State private var showingSetup = false
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

    private var minimumVisionCategorySize: Int {
        VisionCategoryDisplayPolicy.normalizedMinimumSize(
            preference?.minimumVisionCategorySize
                ?? VisionCategoryDisplayPolicy.defaultMinimumSize
        )
    }

    private var dashboardLoadID: CategoryDashboardLoadID {
        CategoryDashboardLoadID(
            refreshToken: dashboardRefreshToken,
            configuration: configuration,
            minimumVisionCategorySize: minimumVisionCategorySize,
            authorizationState: photoLibrary.authorizationState,
            libraryChangeVersion: photoLibrary.changeVersion,
            pendingIdentifiers: pendingItems.map(\.assetIdentifier)
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: .review) {
                NavigationStack {
                    ReviewHomeView(
                        authorizationState: photoLibrary.authorizationState,
                        configuration: configuration,
                        onEditSetup: { showingSetup = true },
                        onStartReviewing: {
                            launchSession(
                                request: ReviewRequest(
                                    configuration: configuration
                                )
                            )
                        },
                        onRequestAuthorization: requestAuthorization,
                        onOpenSettings: photoLibrary.openSystemSettings
                    )
                }
            } label: {
                Label("Review", systemImage: "hand.draw")
            }
            .accessibilityIdentifier(MainTab.review.accessibilityIdentifier)

            Tab(value: .categories) {
                NavigationStack {
                    CategoriesView(
                        authorizationState: photoLibrary.authorizationState,
                        configuration: configuration,
                        hasStartedCategorization: hasStartedCategorization,
                        minimumVisionCategorySize:
                            minimumVisionCategorySize,
                        dashboard: dashboard,
                        photoLibrary: photoLibrary,
                        classificationCoordinator:
                            classificationCoordinator,
                        onEditSetup: { showingSetup = true },
                        onOpenCategory: { category in
                            launchSession(
                                request: ReviewRequest(
                                    configuration: configuration,
                                    category: category
                                )
                            )
                        },
                        onStartCategorization: startCategorization,
                        onRequestAuthorization: requestAuthorization,
                        onOpenSettings: photoLibrary.openSystemSettings
                    )
                }
            } label: {
                Label("Categories", systemImage: "square.grid.2x2")
            }
            .accessibilityIdentifier(
                MainTab.categories.accessibilityIdentifier
            )

            Tab(value: .queue) {
                NavigationStack {
                    PendingDeletionView(
                        photoLibrary: photoLibrary,
                        classificationCoordinator: classificationCoordinator
                    )
                }
            } label: {
                Label("Queue", systemImage: "trash")
                    .accessibilityValue(
                        pendingItems.isEmpty
                            ? "Empty"
                            : "\(pendingItems.count) pending"
                    )
            }
            .badge(pendingItems.count)
            .accessibilityIdentifier(MainTab.queue.accessibilityIdentifier)

            Tab(value: .settings) {
                NavigationStack {
                    SettingsView(
                        photoLibrary: photoLibrary,
                        classificationCoordinator: classificationCoordinator,
                        onCategoryEligibilityChanged: {
                            dashboardRefreshToken = UUID()
                        }
                    )
                }
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier(MainTab.settings.accessibilityIdentifier)
        }
        .sheet(isPresented: $showingSetup) {
            SessionSetupView(configuration: configuration) {
                saveConfiguration($0)
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
        .task(id: dashboardLoadID) {
            guard photoLibrary.authorizationState.canReadLibrary else {
                return
            }
            await dashboard.load(
                configuration: configuration,
                repository: ReviewRepository(modelContext: modelContext),
                photoLibrary: photoLibrary,
                coordinator: classificationCoordinator,
                minimumVisionCategorySize: minimumVisionCategorySize
            )
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

    private func requestAuthorization() {
        Task { _ = await photoLibrary.requestAuthorization() }
    }

    private func saveConfiguration(_ newConfiguration: ReviewConfiguration) {
        do {
            try ReviewRepository(modelContext: modelContext)
                .saveConfiguration(newConfiguration)
            dashboardRefreshToken = UUID()
        } catch {
            errorMessage = error.localizedDescription
        }
        showingSetup = false
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

private struct CategoryDashboardLoadID: Equatable {
    let refreshToken: UUID
    let configuration: ReviewConfiguration
    let minimumVisionCategorySize: Int
    let authorizationState: AuthorizationState
    let libraryChangeVersion: Int
    let pendingIdentifiers: [String]
}
