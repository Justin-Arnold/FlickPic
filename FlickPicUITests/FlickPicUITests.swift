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
        XCTAssertTrue(app.buttons["Continue"].exists)
        XCTAssertEqual(app.alerts.count, 0, "Photos access must not be requested before Continue")
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
            app.staticTexts["Review by Category"].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS 'CancellationError'"))
                .firstMatch
                .waitForExistence(timeout: 2)
        )

        let pending = app.buttons["pending-deletions"]
        XCTAssertTrue(pending.waitForExistence(timeout: 3))
        XCTAssertTrue(pending.isHittable)
        pending.tap()

        let confirmDeletion = app.buttons["Delete 1 Items"]
        XCTAssertTrue(confirmDeletion.waitForExistence(timeout: 3))
        confirmDeletion.tap()
        app.alerts["Delete these items?"].buttons["Continue"].tap()
        XCTAssertTrue(
            app.staticTexts["Deletion Queue Is Empty"]
                .waitForExistence(timeout: 3)
        )
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
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()

        let stepper = app.steppers["minimum-vision-category-size"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 3))
        let decrement = app.buttons[
            "minimum-vision-category-size-Decrement"
        ]
        XCTAssertTrue(decrement.exists)
        for _ in 0..<4 {
            decrement.tap()
        }
        app.buttons["Done"].tap()
    }
}
