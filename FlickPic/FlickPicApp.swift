//
//  FlickPicApp.swift
//  FlickPic
//
//  Created by Justin Arnold on 7/24/26.
//

import SwiftUI
import SwiftData

@main
struct FlickPicApp: App {
    private let modelContainer: ModelContainer
    @State private var photoLibrary: PhotoLibraryService
    @State private var classificationCoordinator: ClassificationCoordinator

    init() {
        let photoLibrary = PhotoLibraryService()
        #if DEBUG
        let classificationCoordinator =
            ProcessInfo.processInfo.arguments.contains("-ui-testing-fixtures")
                ? ClassificationCoordinator(
                    classifier: UITestImageClassificationClient()
                )
                : ClassificationCoordinator()
        #else
        let classificationCoordinator = ClassificationCoordinator()
        #endif
        let schema = Schema([
            ReviewedAsset.self,
            PendingDeletion.self,
            AppPreference.self,
            AssetClassification.self,
            VisionTagAssignment.self
        ])
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: ProcessInfo.processInfo.arguments.contains("-ui-testing")
        )

        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: configuration
            )
        } catch {
            fatalError("Unable to create FlickPic data store: \(error)")
        }

        _photoLibrary = State(initialValue: photoLibrary)
        _classificationCoordinator = State(initialValue: classificationCoordinator)

        let container = modelContainer
        ClassificationBackgroundScheduler.shared.register {
            await classificationCoordinator.runBackgroundIndexing(
                repository: ReviewRepository(modelContext: container.mainContext),
                photoLibrary: photoLibrary
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                photoLibrary: photoLibrary,
                classificationCoordinator: classificationCoordinator
            )
        }
        .modelContainer(modelContainer)
    }
}
