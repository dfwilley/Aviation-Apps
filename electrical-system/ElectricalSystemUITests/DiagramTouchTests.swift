import XCTest

// Runs the real app on a simulator and touches the diagram, to prove the boxes respond.
final class DiagramTouchTests: XCTestCase {

    // Centers of the boxes on the diagram's 340 x 264 drawing grid.
    private func touch(_ app: XCUIApplication, x: CGFloat, y: CGFloat) {
        let diagram = app.descendants(matching: .any)["diagram"].firstMatch
        XCTAssertTrue(diagram.waitForExistence(timeout: 20), "diagram not found")
        diagram.coordinate(withNormalizedOffset: CGVector(dx: x / 340, dy: y / 264)).tap()
    }

    private func text(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    func testTouchingBoxesTogglesThem() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(text(app, startingWith: "Fed by the main alternator").waitForExistence(timeout: 20))

        // Main alternator off: Battery 1 takes the main bus.
        touch(app, x: 48, y: 38)
        XCTAssertTrue(text(app, startingWith: "Fed by Battery 1").waitForExistence(timeout: 5),
                      "touching MAIN ALT did not fail it")

        // The timer starts with the first failure.
        XCTAssertTrue(text(app, startingWith: "Since first failure").waitForExistence(timeout: 5),
                      "the timer did not start")

        // Battery 1 off as well: the main bus has no source.
        touch(app, x: 48, y: 88)
        XCTAssertTrue(text(app, startingWith: "No source. Main alternator and Battery 1").waitForExistence(timeout: 5),
                      "touching BAT 1 did not fail it")

        // Emergency Power on: the EBBS takes over its avionics.
        touch(app, x: 172, y: 142)
        XCTAssertTrue(text(app, startingWith: "Running the left HXr").waitForExistence(timeout: 5),
                      "touching EMER did not switch it on")

        // Main alternator back on: the main bus is fed by it again.
        touch(app, x: 48, y: 38)
        XCTAssertTrue(text(app, startingWith: "Fed by the main alternator").waitForExistence(timeout: 5),
                      "touching MAIN ALT did not restore it")

        // Backup alternator and Battery 2 off: Battery 2 shows as failed.
        touch(app, x: 48, y: 188)
        touch(app, x: 48, y: 238)
        XCTAssertTrue(text(app, startingWith: "Battery 2 is not being charged").exists == false)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Failed")).firstMatch
            .waitForExistence(timeout: 5), "touching BAT 2 did not fail it")
    }
}
