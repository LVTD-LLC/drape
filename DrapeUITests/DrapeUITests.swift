import XCTest

@MainActor final class DrapeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testAddEditAndDeletePiece() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        app.buttons["addPiece"].tap()
        XCTAssertTrue(app.buttons["savePiece"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["savePiece"].isEnabled)
        app.swipeUp()
        app.buttons["testPhoto"].tap()
        let name = app.textFields["itemName"]
        name.tap(); name.typeText("My linen shirt")
        app.buttons["savePiece"].tap()
        let piece = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "My linen shirt")).firstMatch
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

    func testAIRequiresNoCustomerKeyOrUploadDialog() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting", "--seed"]; app.launch()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertFalse(app.secureTextFields["OpenRouter API key"].exists)
        XCTAssertTrue(app.switches["Generate studio photos"].exists)
        app.tabBars.buttons["Wardrobe"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Everyday linen shirt")).firstMatch.tap()
        for _ in 0..<5 {
            if app.buttons["Ask AI"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["Ask AI"].tap()
        XCTAssertFalse(app.alerts["Send photos to OpenRouter?"].exists)
        XCTAssertFalse(app.alerts["Something needs your attention"].exists)
        // UI test launches have no gateway endpoint, so no paid requests are sent.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Drape’s AI service is unavailable")).firstMatch.waitForExistence(timeout: 30))
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
