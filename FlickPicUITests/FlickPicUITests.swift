//
//  FlickPicUITests.swift
//  FlickPicUITests
//
//  Created by Justin Arnold on 7/24/26.
//

import XCTest

final class FlickPicUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testOnboardingExplainsPrivacyBeforeAccess() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        XCTAssertTrue(app.staticTexts["A calmer camera roll"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["On your device"].exists)
        XCTAssertTrue(app.staticTexts["Deletion stays deliberate"].exists)
        XCTAssertTrue(app.staticTexts["Private categorization"].exists)
        XCTAssertTrue(app.staticTexts["No account or tracking"].exists)
        XCTAssertTrue(app.buttons["See How It Works"].exists)
        XCTAssertTrue(app.buttons["Skip Tour"].exists)

        let viewport = app.windows.firstMatch.frame
        let privacyNote = app.descendants(matching: .any)[
            "onboarding-privacy-note"
        ]
        let skipTour = app.buttons["onboarding-skip-tour"]
        let seeHowItWorks = app.buttons["onboarding-start"]
        let initialContent = [
            app.staticTexts["A calmer camera roll"],
            app.staticTexts["On your device"],
            app.staticTexts["Media, history, and categories stay local."],
            app.staticTexts["Deletion stays deliberate"],
            app.staticTexts[
                "Nothing is deleted until you confirm the queue."
            ],
            app.staticTexts["Private categorization"],
            app.staticTexts[
                "Optional Apple Vision categorization stays on-device."
            ],
            app.staticTexts["No account or tracking"],
            app.staticTexts[
                "No backend, analytics, ads, or subscription."
            ],
            privacyNote,
            skipTour,
            seeHowItWorks
        ]
        for element in initialContent {
            XCTAssertTrue(element.exists)
            XCTAssertGreaterThanOrEqual(element.frame.minY, viewport.minY)
            XCTAssertLessThanOrEqual(element.frame.maxY, viewport.maxY)
        }
        XCTAssertLessThan(
            min(skipTour.frame.minY, seeHowItWorks.frame.minY)
                - privacyNote.frame.maxY,
            viewport.height * 0.24,
            "The introduction should distribute space instead of leaving a large empty lower region."
        )
        XCTAssertTrue(skipTour.isHittable)
        XCTAssertTrue(seeHowItWorks.isHittable)
        XCTAssertEqual(
            app.alerts.count,
            0,
            "Photos access must not be requested before the tour."
        )

        app.buttons["onboarding-start"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-step-queue-delete"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertEqual(
            app.alerts.count,
            0,
            "Opening the tour must not request Photos access."
        )
    }

    @MainActor
    func testOnboardingCanSkipTourAndEnterTheApp() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-ui-testing-fixtures"
        ]
        app.launch()

        let skip = app.buttons["onboarding-skip-tour"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        XCTAssertTrue(skip.isHittable)
        skip.tap()

        XCTAssertTrue(
            app.buttons["start-reviewing"].waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testOnboardingSkipCompletesAfterAuthorizationIsDenied() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-ui-testing-fixtures",
            "-ui-testing-denied-authorization"
        ]
        app.launch()

        let skip = app.buttons["onboarding-skip-tour"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()

        XCTAssertTrue(
            app.staticTexts["Photos access is off"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.buttons["onboarding-start"].exists)

        selectTab("tab-queue", in: app)
        XCTAssertTrue(
            app.staticTexts["Deletion Queue Is Empty"]
                .waitForExistence(timeout: 3)
        )
        selectTab("tab-settings", in: app)
        XCTAssertTrue(
            app.staticTexts["Photos Access"].waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testOnboardingRemainsReachableWithAccessibilityText() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["A calmer camera roll"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["onboarding-skip-tour"].isHittable)
        XCTAssertTrue(app.buttons["onboarding-start"].isHittable)

        let finalPromise = app.staticTexts[
            "No backend, analytics, ads, or subscription."
        ]
        XCTAssertTrue(finalPromise.waitForExistence(timeout: 3))

        let viewport = app.windows.firstMatch.frame
        let contentBottom = min(
            app.buttons["onboarding-skip-tour"].frame.minY,
            app.buttons["onboarding-start"].frame.minY
        )
        func isFullyVisible() -> Bool {
            finalPromise.frame.minY >= viewport.minY
                && finalPromise.frame.maxY <= contentBottom
        }

        let start = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0.5,
                dy: max(
                    min(contentBottom / viewport.height - 0.03, 0.8),
                    0.2
                )
            )
        )
        let end = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)
        )
        for _ in 0..<6 where !isFullyVisible() {
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(
            isFullyVisible(),
            """
            Final promise frame \(finalPromise.frame) did not fit between \
            \(viewport.minY) and \(contentBottom).
            """
        )
    }

    @MainActor
    func testOnboardingPracticesEveryCoreReviewGesture() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-ui-testing-fixtures"
        ]
        app.launch()

        let start = app.buttons["onboarding-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()

        let card = app.descendants(matching: .any)["onboarding-demo-card"]
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-step-queue-delete"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        let progress = app.descendants(matching: .any)[
            "onboarding-progress"
        ]
        XCTAssertTrue(progress.exists)
        XCTAssertGreaterThan(card.frame.minY, app.descendants(matching: .any)[
            "onboarding-step-queue-delete"
        ].frame.maxY)
        XCTAssertGreaterThan(progress.frame.minY, card.frame.maxY)
        XCTAssertEqual(app.scrollViews.count, 0)
        card.swipeLeft()

        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-step-keep"]
                .waitForExistence(timeout: 3)
        )
        card.swipeRight()

        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-step-rescue"]
                .waitForExistence(timeout: 3)
        )
        card.swipeUp()

        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-step-inspect"]
                .waitForExistence(timeout: 3)
        )
        card.doubleTap()

        let inspector = app.descendants(matching: .any)["image-inspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 3))
        let closeInspector = app.buttons["Close detail"]
        XCTAssertTrue(closeInspector.waitForExistence(timeout: 3))
        closeInspector.tap()
        XCTAssertTrue(inspector.waitForNonExistence(timeout: 3))

        let continueToPhotos = app.buttons["onboarding-continue"]
        XCTAssertTrue(continueToPhotos.waitForExistence(timeout: 3))
        continueToPhotos.tap()

        XCTAssertTrue(
            app.buttons["start-reviewing"].waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testOnboardingGestureTourOnlyAcceptsTheTaughtDirection() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-ui-testing-fixtures"
        ]
        app.launch()

        let start = app.buttons["onboarding-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()

        XCTAssertFalse(app.staticTexts["A quick tour"].exists)
        XCTAssertFalse(
            app.staticTexts[
                "Practice on this sample—nothing is saved."
            ].exists
        )
        XCTAssertFalse(app.buttons["onboarding-skip"].exists)
        XCTAssertEqual(app.scrollViews.count, 0)

        let card = app.descendants(matching: .any)["onboarding-demo-card"]
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-step-queue-delete"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.swipeRight()
        XCTAssertFalse(
            app.descendants(matching: .any)["onboarding-step-keep"]
                .waitForExistence(timeout: 0.5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-step-queue-delete"]
                .exists
        )
        card.swipeLeft()

        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-step-keep"]
                .waitForExistence(timeout: 3)
        )
        card.swipeLeft()
        XCTAssertFalse(
            app.descendants(matching: .any)["onboarding-step-rescue"]
                .waitForExistence(timeout: 0.5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-step-keep"].exists
        )
        card.swipeRight()

        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-step-rescue"]
                .waitForExistence(timeout: 3)
        )
        card.swipeDown()
        XCTAssertFalse(
            app.descendants(matching: .any)["onboarding-step-inspect"]
                .waitForExistence(timeout: 0.5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-step-rescue"].exists
        )
    }

    @MainActor
    func testOnboardingCanAdvanceWithoutPerformingGestures() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-ui-testing-fixtures"
        ]
        app.launch()

        let start = app.buttons["onboarding-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()

        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        next.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-step-keep"]
                .waitForExistence(timeout: 3)
        )

        next.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-step-rescue"]
                .waitForExistence(timeout: 3)
        )

        next.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-step-inspect"]
                .waitForExistence(timeout: 3)
        )

        let continueToPhotos = app.buttons["onboarding-continue"]
        XCTAssertTrue(continueToPhotos.waitForExistence(timeout: 3))
        continueToPhotos.tap()
        XCTAssertTrue(
            app.buttons["start-reviewing"].waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testOnboardingGestureTourFitsAccessibilityTextWithoutScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let start = app.buttons["onboarding-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()

        let coachMark = app.descendants(matching: .any)[
            "onboarding-step-queue-delete"
        ]
        let card = app.descendants(matching: .any)["onboarding-demo-card"]
        let progress = app.descendants(matching: .any)[
            "onboarding-progress"
        ]
        let next = app.buttons["onboarding-next"]
        let viewport = app.windows.firstMatch.frame

        for element in [coachMark, card, progress, next] {
            XCTAssertTrue(element.waitForExistence(timeout: 3))
            XCTAssertGreaterThanOrEqual(element.frame.minY, viewport.minY)
            XCTAssertLessThanOrEqual(element.frame.maxY, viewport.maxY)
        }
        XCTAssertGreaterThan(card.frame.minY, coachMark.frame.maxY)
        XCTAssertGreaterThan(progress.frame.minY, card.frame.maxY)
        XCTAssertGreaterThan(next.frame.minY, progress.frame.maxY)
        XCTAssertTrue(next.isHittable)
        XCTAssertEqual(app.scrollViews.count, 0)
    }

    @MainActor
    func testMainInterfaceUsesFourFunctionalTabs() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-skip-onboarding",
            "-ui-testing-fixtures"
        ]
        app.launch()

        for identifier in [
            "tab-review",
            "tab-categories",
            "tab-queue",
            "tab-settings"
        ] {
            XCTAssertTrue(
                app.buttons[identifier].waitForExistence(timeout: 3)
            )
        }

        XCTAssertTrue(app.staticTexts["Review"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["scope-filter"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["media-filter"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["review-order"].exists
        )
        XCTAssertFalse(app.buttons["review-setup"].exists)
        XCTAssertTrue(app.buttons["start-reviewing"].isHittable)
        XCTAssertFalse(app.staticTexts["FlickPic"].exists)
        XCTAssertFalse(
            app.staticTexts["Keep what matters. Queue the rest."].exists
        )

        selectTab("tab-categories", in: app)
        XCTAssertTrue(app.staticTexts["Media Types"].exists)
        XCTAssertTrue(app.staticTexts["On-Device Categories"].exists)
        XCTAssertTrue(app.buttons["categories-review-setup"].exists)

        selectTab("tab-queue", in: app)
        XCTAssertTrue(
            app.staticTexts["Deletion Queue Is Empty"]
                .waitForExistence(timeout: 3)
        )

        selectTab("tab-settings", in: app)
        XCTAssertTrue(app.staticTexts["Photos Access"].exists)
        XCTAssertFalse(app.buttons["Done"].exists)

        selectTab("tab-review", in: app)
        XCTAssertTrue(app.buttons["start-reviewing"].isHittable)
    }

    @MainActor
    func testReviewSetupStaysSynchronizedAcrossTabs() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-skip-onboarding",
            "-ui-testing-fixtures"
        ]
        app.launch()

        let mediaPicker = app.descendants(matching: .any)["media-filter"]
        XCTAssertTrue(mediaPicker.waitForExistence(timeout: 3))
        mediaPicker.tap()
        app.buttons["Videos"].tap()
        XCTAssertTrue(mediaPicker.label.contains("Videos"))

        selectTab("tab-categories", in: app)
        let categorySetup = app.buttons["categories-review-setup"]
        XCTAssertTrue(categorySetup.waitForExistence(timeout: 3))
        XCTAssertTrue(categorySetup.label.contains("Videos"))
        XCTAssertTrue(
            app.buttons["category-metadata:videos"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.buttons["category-metadata:images"].exists)
    }

    @MainActor
    func testMetadataBucketsAppearBeforeVisionStarts() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-skip-onboarding",
            "-ui-testing-fixtures"
        ]
        app.launch()
        selectTab("tab-categories", in: app)

        XCTAssertTrue(
            app.buttons["category-metadata:images"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["category-metadata:videos"].exists)
        XCTAssertTrue(app.buttons["category-metadata:gifs"].exists)
        XCTAssertTrue(app.buttons["category-metadata:screenshots"].exists)
        XCTAssertTrue(app.buttons["category-metadata:panoramas"].exists)
        XCTAssertTrue(app.buttons["start-categorizing"].exists)
        XCTAssertFalse(app.buttons["category-vision:dog"].exists)
    }

    @MainActor
    func testMetadataCategoryHitTargetsDoNotOverlap() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-skip-onboarding",
            "-ui-testing-fixtures"
        ]
        app.launch()
        selectTab("tab-categories", in: app)

        let gifs = app.buttons["category-metadata:gifs"]
        let screenshots = app.buttons["category-metadata:screenshots"]
        XCTAssertTrue(gifs.waitForExistence(timeout: 3))
        XCTAssertTrue(screenshots.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(
            gifs.frame.maxX,
            screenshots.frame.minX,
            "Adjacent category buttons must have disjoint hit targets."
        )

        gifs.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["animated-gif-badge"]
                .waitForExistence(timeout: 3),
            "Tapping GIFs must open the GIF deck, not an overlapping category."
        )
    }

    @MainActor
    func testCloudVideoShowsAnActionableRetryMessage() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-skip-onboarding",
            "-ui-testing-fixtures",
            "-ui-testing-cloud-video-thumbnail"
        ]
        app.launch()
        selectTab("tab-categories", in: app)

        let videos = app.buttons["category-metadata:videos"]
        XCTAssertTrue(videos.waitForExistence(timeout: 3))
        videos.tap()

        XCTAssertTrue(
            app.staticTexts[
                "This item needs to download from iCloud. Check your connection and try again."
            ]
            .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["Retry"].exists)
        XCTAssertTrue(app.buttons["Later"].exists)
        XCTAssertFalse(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS 'PHPhotosErrorDomain'"))
                .firstMatch
                .exists
        )
    }

    @MainActor
    func testVisionBucketOpensWhileAnotherMatchIsStillArriving() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-skip-onboarding",
            "-ui-testing-fixtures"
        ]
        app.launch()
        selectTab("tab-categories", in: app)

        setVisionCategoryMinimumToOne(in: app)

        let start = app.buttons["start-categorizing"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()

        let dogs = app.buttons["category-vision:dog"]
        XCTAssertTrue(dogs.waitForExistence(timeout: 3))
        dogs.tap()

        XCTAssertTrue(app.staticTexts["1 of 1"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts["1 of 2"].waitForExistence(timeout: 8),
            "The active deck should grow when the second Vision result arrives."
        )
    }

    @MainActor
    func testVisionCategoryMinimumHidesAndRevealsExistingBuckets() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-skip-onboarding",
            "-ui-testing-fixtures"
        ]
        app.launch()
        selectTab("tab-categories", in: app)

        let start = app.buttons["start-categorizing"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()

        let counts = app.descendants(matching: .any)["vision-category-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 3))
        let finalCounts = NSPredicate(
            format: "label == %@",
            "2 found · 0 shown"
        )
        expectation(for: finalCounts, evaluatedWith: counts)
        waitForExpectations(timeout: 8)
        XCTAssertFalse(app.buttons["category-vision:dog"].exists)

        setVisionCategoryMinimumToOne(in: app)

        XCTAssertTrue(
            app.buttons["category-vision:dog"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["category-vision:document"].exists)
        XCTAssertEqual(counts.label, "2 found · 2 shown")
    }

    @MainActor
    func testGIFDeckCanOpenAndConfirmPendingDeletions() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-skip-onboarding",
            "-ui-testing-fixtures",
            "-ui-testing-delayed-dashboard-refresh"
        ]
        app.launch()
        selectTab("tab-categories", in: app)

        let gifs = app.buttons["category-metadata:gifs"]
        XCTAssertTrue(gifs.waitForExistence(timeout: 3))
        gifs.tap()

        XCTAssertTrue(app.staticTexts["1 of 1"].waitForExistence(timeout: 3))
        app.buttons["Delete"].tap()
        XCTAssertTrue(
            app.staticTexts["Nothing to Review"].waitForExistence(timeout: 3)
        )
        app.buttons["End Session"].firstMatch.tap()

        XCTAssertTrue(
            app.staticTexts["Media Types"].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS 'CancellationError'"))
                .firstMatch
                .waitForExistence(timeout: 2)
        )

        let queueTab = app.buttons["tab-queue"]
        XCTAssertTrue(queueTab.waitForExistence(timeout: 3))
        XCTAssertEqual(queueTab.value as? String, "1 pending")
        queueTab.tap()

        let confirmDeletion = app.buttons["Delete 1 Items"]
        XCTAssertTrue(confirmDeletion.waitForExistence(timeout: 3))
        confirmDeletion.tap()
        app.alerts["Delete these items?"].buttons["Continue"].tap()
        XCTAssertTrue(
            app.staticTexts["Deletion Queue Is Empty"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertEqual(queueTab.value as? String, "Empty")
    }

    @MainActor
    func testPhotoInspectorZoomsAndReturnsToTheSameDeckPosition() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-skip-onboarding",
            "-ui-testing-fixtures"
        ]
        app.launch()

        let startReviewing = app.buttons["start-reviewing"]
        XCTAssertTrue(startReviewing.waitForExistence(timeout: 3))
        startReviewing.tap()

        let initialPosition = app.staticTexts["1 of 3"]
        XCTAssertTrue(initialPosition.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["animated-gif-badge"]
                .waitForExistence(timeout: 3)
        )

        XCTAssertFalse(app.buttons["inspect-details"].exists)
        let inspectableMedia = app.descendants(matching: .any)["inspectable-media"]
        XCTAssertTrue(inspectableMedia.waitForExistence(timeout: 3))
        XCTAssertTrue(inspectableMedia.isHittable)
        inspectableMedia.doubleTap()

        let fit = app.buttons["Fit whole image"]
        let zoomIn = app.buttons["Zoom in"]
        XCTAssertTrue(fit.waitForExistence(timeout: 3))
        XCTAssertTrue(zoomIn.exists)
        zoomIn.tap()
        fit.tap()
        app.buttons["Close detail"].tap()

        XCTAssertTrue(initialPosition.waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments.append("-ui-testing")
            app.launch()
        }
    }

    @MainActor
    private func setVisionCategoryMinimumToOne(
        in app: XCUIApplication
    ) {
        selectTab("tab-settings", in: app)

        let stepper = app.steppers["minimum-vision-category-size"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 3))
        let decrement = app.buttons[
            "minimum-vision-category-size-Decrement"
        ]
        XCTAssertTrue(decrement.exists)
        for _ in 0..<4 {
            decrement.tap()
        }
        selectTab("tab-categories", in: app)
    }

    @MainActor
    private func selectTab(
        _ accessibilityIdentifier: String,
        in app: XCUIApplication
    ) {
        let tab = app.buttons[accessibilityIdentifier]
        XCTAssertTrue(tab.waitForExistence(timeout: 3))
        XCTAssertTrue(tab.isHittable)
        tab.tap()
    }
}
