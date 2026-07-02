import XCTest

// Drives the real BakeEditView through the network-free UITestHost
// (launch argument -uiTestHost).
//
// Locale assumption: these tests expect a 12-hour US-format simulator. The
// picker-wheel indices (date, hour, minute, AM/PM) and the "h:mm" capsule
// text both shift under a 24-hour or non-US locale.
final class BakeEditUITests: XCTestCase {

    // Verifies the schedule-row date/time capsule: tapping it opens the
    // combined date+time wheel popover, turning the minute wheel updates the
    // capsule text, and the popover dismisses.
    @MainActor
    func testCapsuleOpensWheelsAndUpdates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestHost"]
        app.launch()

        // The host presents the edit sheet after ~1s.
        let addStep = app.buttons["Add Step"]
        XCTAssertTrue(addStep.waitForExistence(timeout: 10), "Edit sheet did not appear")

        // Insert a fresh row — the historically glitchy case.
        addStep.tap()

        // Newest row's capsule is the last date-and-time capsule in the form.
        let capsule = try XCTUnwrap(
            app.buttons.matching(identifier: "dateTimeCapsule").allElementsBoundByIndex.last,
            "No date-and-time capsule found"
        )
        let valueBefore = capsule.value as? String

        capsule.tap()

        // Combined wheels: date, hour, minute, AM/PM.
        let minuteWheel = app.pickerWheels.element(boundBy: 2)
        XCTAssertTrue(minuteWheel.waitForExistence(timeout: 5), "Wheel popover did not open on tap")
        XCTAssertGreaterThanOrEqual(app.pickerWheels.count, 3, "Expected combined date+time wheels")

        // The new row defaults to .now, so a fixed target minute is a no-op
        // (and a test failure) once an hour — pick one the row isn't showing.
        let targetMinute = valueBefore?.contains("37") == true ? "38" : "37"
        minuteWheel.adjust(toPickerWheelValue: targetMinute)

        // PopoverDismissRegion is a private UIKit accessibility identifier —
        // stable across recent iOS releases but unversioned; revisit here
        // first if popover dismissal breaks on a new iOS.
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        dismissRegion.tap()
        XCTAssertTrue(waitForDisappearance(of: dismissRegion, timeout: 5), "Wheel popover did not dismiss")

        let valueAfter = capsule.value as? String
        XCTAssertNotEqual(valueBefore, valueAfter, "Capsule text did not change after adjusting the wheel")
        XCTAssertTrue(valueAfter?.contains(targetMinute) == true, "Capsule does not show the picked minute (got \(valueAfter ?? "nil"))")
    }

    @MainActor
    func testAddedRowsAreRevealedAboveKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestHost"]
        app.launch()

        let addIngredient = app.buttons["Add Ingredient"]
        XCTAssertTrue(addIngredient.waitForExistence(timeout: 10), "Edit sheet did not appear")

        // First ingredient: focus jumps to the new name field and the keyboard rises.
        addIngredient.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "Keyboard did not appear after Add Ingredient")
        app.typeText("Flour")

        // Second ingredient while the keyboard is already up — the row Greg
        // reported as hidden. The new name field must sit above the keyboard.
        addIngredient.tap()
        sleepPastRevealPasses()

        let nameField = try XCTUnwrap(
            app.textFields.matching(identifier: "Name").allElementsBoundByIndex.last,
            "No new ingredient name field"
        )
        XCTAssertTrue(nameField.isHittable, "New ingredient field is not visible")
        XCTAssertLessThan(nameField.frame.maxY, keyboard.frame.minY, "New ingredient field is under the keyboard")
        app.typeText("Water")
        XCTAssertEqual(nameField.value as? String, "Water", "Typing did not land in the new ingredient field")

        // Add Step (keyboard dismissed first — the button sits below it): the
        // new row lands below the fold, must scroll into view, and the Action
        // field must take focus so typing lands there immediately.
        app.buttons["Done"].tap()
        XCTAssertTrue(waitForDisappearance(of: keyboard, timeout: 5), "Keyboard did not dismiss")

        let addStep = app.buttons["Add Step"]
        addStep.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "Keyboard did not appear after Add Step (Action field not focused)")
        sleepPastRevealPasses()

        let actionField = try XCTUnwrap(
            app.textFields.matching(identifier: "Action (e.g., Mix, fold, shape)").allElementsBoundByIndex.last,
            "No new step action field"
        )
        XCTAssertTrue(actionField.isHittable, "New step action field is not visible")
        XCTAssertLessThan(actionField.frame.maxY, keyboard.frame.minY, "New step action field is under the keyboard")
        app.typeText("Fold")
        XCTAssertEqual(actionField.value as? String, "Fold", "Typing did not land in the new step's Action field")
    }

    /// Waits out both KeyboardReveal passes (0.45s / 0.9s — see
    /// KeyboardReveal.passDelays in the app target) plus the scroll animation.
    /// Bump this if those delays grow.
    private func sleepPastRevealPasses() {
        Thread.sleep(forTimeInterval: 1.2)
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
