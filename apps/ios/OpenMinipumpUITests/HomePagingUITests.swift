// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// The home screen has two pages ("Jetzt", "Ausblick"). Swiping sideways switches them,
/// except on the chart, where a sideways drag moves the selection instead.
final class HomePagingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demoData"]
        app.launch()
    }

    private var outlookVisible: Bool { app.staticTexts["Vorrat"].isHittable }

    func testSwipeSwitchesPagesBothWays() {
        let value = app.buttons["Jetzt"]
        XCTAssertTrue(value.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Vorrat"].exists && outlookVisible)
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Vorrat"].waitForExistence(timeout: 3))
        XCTAssertTrue(outlookVisible, "swipe left must open the outlook page")
        app.swipeRight()
        XCTAssertTrue(app.otherElements["glucoseChart"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["glucoseChart"].isHittable, "swipe right must return to the first page")
    }

    func testSwipeOnChartDoesNotSwitchPage() {
        let chart = app.otherElements["glucoseChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        chart.swipeLeft()
        XCTAssertTrue(chart.isHittable, "a sideways drag on the chart scrubs, the page stays")
        // Paging must still work afterwards (the chart lock must not stick).
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Vorrat"].waitForExistence(timeout: 3))
        XCTAssertTrue(outlookVisible, "paging must work again after scrubbing the chart")
    }

    func testSwitcherTap() {
        XCTAssertTrue(app.buttons["Ausblick"].waitForExistence(timeout: 10))
        app.buttons["Ausblick"].tap()
        XCTAssertTrue(app.staticTexts["Vorrat"].waitForExistence(timeout: 3))
        app.buttons["Jetzt"].tap()
        XCTAssertTrue(app.otherElements["glucoseChart"].waitForExistence(timeout: 3))
    }

    func testPreviewOpensOutlook() {
        let preview = app.buttons["outlookPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        if !preview.isHittable { app.swipeUp() }
        preview.tap()
        XCTAssertTrue(app.staticTexts["Vorrat"].waitForExistence(timeout: 3))
        XCTAssertTrue(outlookVisible, "tapping the preview must open the outlook page")
    }
}
