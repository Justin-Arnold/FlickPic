//
//  ContentView.swift
//  FlickPic
//
//  Created by Justin Arnold on 7/24/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var preferences: [AppPreference]

    let photoLibrary: PhotoLibraryService
    let classificationCoordinator: ClassificationCoordinator

    private var hasCompletedOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("-skip-onboarding")
            || preferences.first(where: { $0.key == "primary" })?.hasCompletedOnboarding == true
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                HomeView(
                    photoLibrary: photoLibrary,
                    classificationCoordinator: classificationCoordinator
                )
            } else {
                OnboardingView(photoLibrary: photoLibrary) {
                    try? ReviewRepository(modelContext: modelContext).completeOnboarding()
                }
            }
        }
        .task {
            _ = try? ReviewRepository(modelContext: modelContext).preference()
            startAutomaticIndexingIfPossible()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                photoLibrary.refreshAuthorizationState()
                startAutomaticIndexingIfPossible()
            } else if newPhase == .background {
                classificationCoordinator.cancelCurrentWork()
                if photoLibrary.authorizationState.canReadLibrary {
                    ClassificationBackgroundScheduler.shared.schedule()
                }
            }
        }
        .onChange(of: photoLibrary.changeVersion) {
            startAutomaticIndexingIfPossible()
        }
        .onChange(of: photoLibrary.authorizationState) {
            startAutomaticIndexingIfPossible()
        }
        .onChange(of: hasCompletedOnboarding) {
            startAutomaticIndexingIfPossible()
        }
    }

    private func startAutomaticIndexingIfPossible() {
        guard hasCompletedOnboarding,
              scenePhase == .active,
              photoLibrary.authorizationState.canReadLibrary else {
            return
        }
        classificationCoordinator.startAutomaticIndexing(
            repository: ReviewRepository(modelContext: modelContext),
            photoLibrary: photoLibrary
        )
    }
}

#Preview {
    ContentView(
        photoLibrary: PhotoLibraryService(),
        classificationCoordinator: ClassificationCoordinator()
    )
        .modelContainer(
            for: [
                ReviewedAsset.self,
                PendingDeletion.self,
                AppPreference.self,
                AssetClassification.self
            ],
            inMemory: true
        )
}
