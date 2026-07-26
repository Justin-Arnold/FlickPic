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
    func testCategorySelectionForcesPhotosWithoutHidingOtherFilters() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-skip-onboarding",
            "-ui-testing-fixtures"
        ]
        app.launch()

        let setup = app.buttons["review-setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 3))
        setup.tap()

        let category = app.descendants(matching: .any)["category-filter"]
        XCTAssertTrue(category.waitForExistence(timeout: 3))
        category.tap()
        app.buttons["Receipts"].tap()

        let media = app.descendants(matching: .any)["media-filter"]
        XCTAssertTrue(media.exists)
        XCTAssertTrue(media.label.contains("Photos"))
        XCTAssertFalse(media.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["scope-filter"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["review-order"].exists)
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

        let inspect = app.buttons["inspect-details"]
        XCTAssertTrue(inspect.waitForExistence(timeout: 3))
        inspect.tap()

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
}
