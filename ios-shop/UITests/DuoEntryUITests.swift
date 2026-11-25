import XCTest

/** CI-only driver for the Duo screenshot capture (duo-shots-ci branch): taps past the splash
 *  into the real shop, then holds the session open so the workflow can pose the Duo and
 *  screenshot each display from the host with simctl. Not part of any release scheme. */
final class DuoEntryUITests: XCTestCase {
    func testEnterAndHold() throws {
        let app = XCUIApplication()
        app.launch()
        var enter = app.buttons["E N T E R"]
        if !enter.waitForExistence(timeout: 45) {
            enter = app.buttons["ENTER"]
        }
        if enter.exists {
            enter.tap()
            NSLog("DUO-MARKER-ENTERED")
        } else {
            NSLog("DUO-MARKER-NO-ENTER")
        }
        sleep(600)
    }
}
