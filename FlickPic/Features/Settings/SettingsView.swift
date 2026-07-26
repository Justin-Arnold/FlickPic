import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [AppPreference]

    let photoLibrary: PhotoLibraryService
    let classificationCoordinator: ClassificationCoordinator

    @State private var hapticsEnabled = true
    @State private var minimumVisionCategorySize =
        VisionCategoryDisplayPolicy.defaultMinimumSize
    @State private var showingResetConfirmation = false
    @State private var showingRebuildConfirmation = false
    @State private var errorMessage: String?

    private var preference: AppPreference? {
        preferences.first(where: { $0.key == "primary" })
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Access", value: accessDescription)

                if photoLibrary.authorizationState == .limited {
                    Button("Manage Selected Photos") {
                        photoLibrary.presentLimitedLibraryPicker()
                    }
                } else if !photoLibrary.authorizationState.canReadLibrary {
                    Button("Open System Settings") {
                        photoLibrary.openSystemSettings()
                    }
                }
            } header: {
                Text("Photos Access")
            } footer: {
                Text("FlickPic needs read and write access to show your library and delete only items you explicitly confirm.")
            }

            Section {
                LabeledContent(
                    "Status",
                    value: classificationCoordinator.statusDescription
                )

                if classificationCoordinator.isIndexing {
                    ProgressView(
                        value: Double(classificationCoordinator.completedCount),
                        total: Double(max(classificationCoordinator.totalCount, 1))
                    )
                }

                if let classificationError = classificationCoordinator.lastErrorMessage {
                    Text(classificationError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Stepper(
                    value: $minimumVisionCategorySize,
                    in: VisionCategoryDisplayPolicy.minimumSizeRange
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Minimum Category Size")
                        Text(minimumCategorySizeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("minimum-vision-category-size")
                .onChange(of: minimumVisionCategorySize) { _, newValue in
                    guard newValue != preference?.minimumVisionCategorySize else {
                        return
                    }
                    do {
                        try ReviewRepository(modelContext: modelContext)
                            .setMinimumVisionCategorySize(newValue)
                    } catch {
                        minimumVisionCategorySize =
                            VisionCategoryDisplayPolicy.normalizedMinimumSize(
                                preference?.minimumVisionCategorySize
                                    ?? VisionCategoryDisplayPolicy
                                        .defaultMinimumSize
                            )
                        errorMessage = error.localizedDescription
                    }
                }

                if classificationCoordinator.failedCount > 0 {
                    Button("Retry Failed Items") {
                        do {
                            try classificationCoordinator.retryFailed(
                                repository: ReviewRepository(modelContext: modelContext)
                            )
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }

                Button("Rebuild Classification Index", role: .destructive) {
                    showingRebuildConfirmation = true
                }
            } header: {
                Text("On-Device Categories")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "Vision categories appear after at least \(minimumVisionCategorySize) eligible matches under the current review setup. Changing this does not rescan your library."
                    )
                    Text("Apple Vision examines small previews locally. An item can have several category tags. FlickPic never stores OCR text or embeddings.")
                }
            }

            Section {
                Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                    .onChange(of: hapticsEnabled) { _, newValue in
                        do {
                            try ReviewRepository(modelContext: modelContext)
                                .setHapticsEnabled(newValue)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }

                Button("Reset Review History", role: .destructive) {
                    showingResetConfirmation = true
                }
            } header: {
                Text("Review")
            } footer: {
                Text("Resetting makes kept items eligible for review again. It does not change your pending deletion queue or Photos library.")
            }

            Section {
                Label("No account", systemImage: "person.crop.circle.badge.xmark")
                Label("No analytics or tracking", systemImage: "hand.raised")
                Label("No developer-operated server", systemImage: "network.slash")
            } header: {
                Text("Privacy")
            } footer: {
                Text("PhotoKit may retrieve media from your own iCloud Photos library. Sharing occurs only when you choose a destination.")
            }

            Section("Open Source") {
                LabeledContent("License", value: "MIT")
                LabeledContent("Version", value: appVersion)
                Text("The public source repository link will be added before release.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            hapticsEnabled = preference?.hapticsEnabled ?? true
            minimumVisionCategorySize =
                VisionCategoryDisplayPolicy.normalizedMinimumSize(
                    preference?.minimumVisionCategorySize
                        ?? VisionCategoryDisplayPolicy.defaultMinimumSize
                )
        }
        .alert("Reset review history?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                do {
                    try ReviewRepository(modelContext: modelContext).resetReviewHistory()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("Every kept item will become eligible for review again.")
        }
        .alert(
            "Rebuild classification index?",
            isPresented: $showingRebuildConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Rebuild", role: .destructive) {
                Task {
                    do {
                        try await classificationCoordinator.rebuild(
                            repository: ReviewRepository(modelContext: modelContext)
                        )
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Saved Vision tags will be removed and rebuilt automatically. Metadata categories, your Photos library, and review decisions will not change.")
        }
        .alert(
            "Couldn’t Save Changes",
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

    private var accessDescription: String {
        switch photoLibrary.authorizationState {
        case .notDetermined: "Not Requested"
        case .full: "Full Library"
        case .limited: "Selected Photos"
        case .denied: "Denied"
        case .restricted: "Restricted"
        }
    }

    private var minimumCategorySizeDescription: LocalizedStringKey {
        if minimumVisionCategorySize == 1 {
            "1 eligible photo"
        } else {
            "\(minimumVisionCategorySize) eligible photos"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
        return version
    }
}
