import XCTest

@MainActor final class DrapeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    func testRichDetailsCanBeEditedAndFilteredByTag() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting", "--seed"]; app.launch()
        let shirt = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Everyday linen shirt")).firstMatch
        XCTAssertTrue(shirt.waitForExistence(timeout: 10)); shirt.tap()
        app.buttons["Piece options"].tap(); app.buttons["Edit details"].tap()
        // Resolve lazily after scrolling: off-screen Form rows do not exist yet.
        let tagField = app.descendants(matching: .any).matching(identifier: "editTags").firstMatch
        reveal(tagField, in: app); tagField.tap(); tagField.typeText("summer, travel, SUMMER")
        let amount = app.textFields["editPrice"]
        reveal(amount, in: app); amount.tap(); amount.typeText("89.95")
        let currency = app.textFields["editCurrency"]
        reveal(currency, in: app); currency.tap(); currency.typeText("EUR")
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Richer item editor"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["saveDetails"].tap()
        let savedTags = app.staticTexts["itemTags"]
        reveal(savedTags, in: app)
        XCTAssertEqual(savedTags.label, "summer · travel")
        let savedPrice = app.staticTexts["itemPrice"]
        reveal(savedPrice, in: app); XCTAssertEqual(savedPrice.label, "EUR 89.95")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Filter and group wardrobe"].tap()
        let tagToggle = app.switches["filterTag-travel"]
        reveal(tagToggle, in: app)
        tagToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let filterAttachment = XCTAttachment(screenshot: app.screenshot()); filterAttachment.name = "Wardrobe filters"; filterAttachment.lifetime = .keepAlways; add(filterAttachment)
        app.buttons["Done"].tap()
        XCTAssertTrue(shirt.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 matching piece"].exists)
        app.buttons["Clear filters"].tap()
        XCTAssertFalse(app.staticTexts["1 matching piece"].exists)
    }
    func testAddEditAndDeletePiece() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        app.buttons["addPiece"].tap()
        XCTAssertTrue(app.buttons["savePiece"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["savePiece"].isEnabled)
        app.swipeUp()
        app.buttons["testPhoto"].tap()
        XCTAssertFalse(app.textFields["itemName"].exists)
        app.swipeUp()
        app.buttons["testPhoto"].tap()
        app.swipeUp()
        app.buttons["savePiece"].tap()
        let piece = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "New piece")).firstMatch
        XCTAssertTrue(piece.waitForExistence(timeout: 10)); piece.tap()
        app.buttons["Piece options"].tap()
        app.buttons["Edit details"].tap()
        let field = app.textFields["editName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 100))
        field.typeText("Sunday shirt")
        app.buttons["saveDetails"].tap()
        XCTAssertTrue(app.staticTexts["Sunday shirt"].waitForExistence(timeout: 5))
        app.buttons["Piece options"].tap(); app.buttons["Delete piece"].tap()
        app.buttons["Delete piece"].tap()
        XCTAssertTrue(app.staticTexts["Start with a favorite."].waitForExistence(timeout: 5))
    }

    func testCaptureAndDetailHaveNoReviewOrRepeatedAIControls() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        app.buttons["addPiece"].tap()
        XCTAssertFalse(app.textFields["itemName"].exists)
        XCTAssertFalse(app.buttons["Front photo, not added"].exists)
        app.swipeUp()
        app.buttons["testPhoto"].tap(); app.swipeUp(); app.buttons["testPhoto"].tap(); app.swipeUp()
        app.buttons["Save photos only"].tap()
        let piece = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "New piece")).firstMatch
        XCTAssertTrue(piece.waitForExistence(timeout: 10)); piece.tap()
        let position = app.staticTexts["photoPosition"]
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        let previous = position.label
        let carousel = app.descendants(matching: .any).matching(identifier: "photoCarousel").firstMatch
        carousel.swipeLeft()
        XCTAssertNotEqual(position.label, previous)
        XCTAssertFalse(app.buttons["Review AI suggestions"].exists)
        XCTAssertFalse(app.buttons["Ask AI"].exists)
        XCTAssertFalse(app.buttons["Prepare photo"].exists)
        reveal(app.buttons["Finish preparing"], in: app)
    }

    func testCreateLookFromWardrobe() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting", "--seed"]; app.launch()
        app.tabBars.buttons["Looks"].tap()
        app.buttons["Create a look"].tap()
        let name = app.textFields["lookName"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Saturday coffee")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Everyday linen shirt")).firstMatch.tap()
        app.buttons["saveLook"].tap()
        XCTAssertTrue(app.staticTexts["Saturday coffee"].waitForExistence(timeout: 5))
    }

    func testSearchFiltersAndSettingsPrivacy() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting", "--seed"]; app.launch()
        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("No such garment")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "No Results")).firstMatch.waitForExistence(timeout: 5))
        if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        else { app.buttons["Cancel"].tap() }
        app.tabBars.buttons["Settings"].tap()
        app.swipeUp()
        app.buttons["Privacy & your photos"].tap()
        XCTAssertTrue(app.staticTexts["On your iPhone"].waitForExistence(timeout: 5))
    }
}
