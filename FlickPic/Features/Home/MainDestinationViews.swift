import SwiftUI

struct ReviewHomeView: View {
    let authorizationState: AuthorizationState
    let configuration: ReviewConfiguration
    let onChangeConfiguration: (ReviewConfiguration) -> Void
    let onStartReviewing: () -> Void
    let onRequestAuthorization: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Group {
            switch authorizationState {
            case .full, .limited:
                Form {
                    if authorizationState == .limited {
                        LimitedPhotosNotice()
                    }

                    ReviewConfigurationSections(
                        configuration: Binding(
                            get: { configuration },
                            set: { newConfiguration in
                                onChangeConfiguration(newConfiguration)
                            }
                        )
                    )
                }
                .accessibilityIdentifier("review-configuration")

            case .notDetermined:
                ScrollView {
                    PermissionCard(
                        title: "Photos access is needed",
                        detail: "Choose which photos and videos FlickPic can help you review.",
                        buttonTitle: "Continue",
                        action: onRequestAuthorization
                    )
                    .padding()
                }

            case .denied, .restricted:
                ScrollView {
                    PermissionCard(
                        title: "Photos access is off",
                        detail: "Enable read and write access in Settings to review your library.",
                        buttonTitle: "Open Settings",
                        action: onOpenSettings
                    )
                    .padding()
                }
            }
        }
        .navigationTitle("Review")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if authorizationState.canReadLibrary {
                Button(action: onStartReviewing) {
                    Label("Start Reviewing", systemImage: "hand.draw")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .accessibilityIdentifier("start-reviewing")
            }
        }
    }
}

struct CategoriesView: View {
    let authorizationState: AuthorizationState
    let configuration: ReviewConfiguration
    let hasStartedCategorization: Bool
    let minimumVisionCategorySize: Int
    let dashboard: CategoryDashboardModel
    let photoLibrary: PhotoLibraryService
    let classificationCoordinator: ClassificationCoordinator
    let onEditSetup: () -> Void
    let onOpenCategory: (ReviewCategory) -> Void
    let onStartCategorization: () -> Void
    let onRequestAuthorization: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                switch authorizationState {
                case .full, .limited:
                    if authorizationState == .limited {
                        LimitedPhotosNotice()
                    }

                    ReviewSetupButton(
                        configuration: configuration,
                        accessibilityIdentifier: "categories-review-setup",
                        action: onEditSetup
                    )
                    metadataCategories
                    visionCategories
                case .notDetermined:
                    PermissionCard(
                        title: "Photos access is needed",
                        detail: "Choose which photos and videos FlickPic can help you review.",
                        buttonTitle: "Continue",
                        action: onRequestAuthorization
                    )
                case .denied, .restricted:
                    PermissionCard(
                        title: "Photos access is off",
                        detail: "Enable read and write access in Settings to review your library.",
                        buttonTitle: "Open Settings",
                        action: onOpenSettings
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Categories")
    }

    @ViewBuilder
    private var metadataCategories: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Media Types")
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
        }
    }

    @ViewBuilder
    private var visionCategories: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("On-Device Categories")
                .font(.title2.bold())

            if hasStartedCategorization {
                categorizationStatus

                if dashboard.visionBuckets.isEmpty {
                    visionCategoryEmptyMessage
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    bucketGrid(dashboard.visionBuckets)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        "Discover more categories",
                        systemImage: "sparkles"
                    )
                    .font(.headline)
                    Text(
                        "Apple Vision can privately find categories such as pets, food, places, and documents. Results stay on this iPhone."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Button(
                        "Start Categorizing",
                        action: onStartCategorization
                    )
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
                Text(
                    "\(dashboard.discoveredVisionCategoryCount) found · \(dashboard.visibleVisionCategoryCount) shown"
                )
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityIdentifier("vision-category-counts")
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

    private var visionCategoryEmptyMessage: Text {
        if classificationCoordinator.isIndexing {
            Text(
                "Vision categories appear after at least \(minimumVisionCategorySize) eligible matches are found."
            )
        } else if dashboard.discoveredVisionCategoryCount > 0 {
            Text(
                "No Vision categories have at least \(minimumVisionCategorySize) eligible matches for this review setup."
            )
        } else {
            Text("No Vision categories match this review setup yet.")
        }
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
                    onOpenCategory(bucket.category)
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
}

struct ReviewSetupButton: View {
    let configuration: ReviewConfiguration
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.title3)
                    .foregroundStyle(.indigo)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Review Setup")
                        .font(.headline)
                    Text(configuration.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Review setup, \(configuration.summary)")
        .accessibilityHint("Edits which items are eligible for review")
        .accessibilityIdentifier(accessibilityIdentifier)
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
                                Image(
                                    systemName: bucket.category.systemImage
                                )
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

private struct LimitedPhotosNotice: View {
    var body: some View {
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
}

private struct PermissionCard: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let buttonTitle: LocalizedStringKey
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
