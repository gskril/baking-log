import XCTest

// Verifies the schedule-row date/time capsule: tapping it opens the combined
// date+time wheel popover, turning the minute wheel updates the capsule text,
// and the popover dismisses.
final class CompactDateTimePickerUITests: XCTestCase {

    @MainActor
    func testCapsuleOpensWheelsAndUpdates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-datePickerRepro"]
        app.launch()

        // The repro host presents the real BakeEditView sheet after ~1s.
        let addStep = app.buttons["Add Step"]
        XCTAssertTrue(addStep.waitForExistence(timeout: 10), "Edit sheet did not appear")

        // Insert a fresh row — the historically glitchy case.
        addStep.tap()

        // Newest row's capsule is the last "Date and time" button in the form.
        let capsule = app.buttons.matching(identifier: "Date and time").allElementsBoundByIndex.last!
        XCTAssertTrue(capsule.exists, "No date-and-time capsule found")
        let valueBefore = capsule.value as? String

        capsule.tap()

        // Combined wheels: date, hour, minute, AM/PM.
        let minuteWheel = app.pickerWheels.element(boundBy: 2)
        XCTAssertTrue(minuteWheel.waitForExistence(timeout: 5), "Wheel popover did not open on tap")
        XCTAssertGreaterThanOrEqual(app.pickerWheels.count, 3, "Expected combined date+time wheels")
        minuteWheel.adjust(toPickerWheelValue: "37")

        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        dismissRegion.tap()
        XCTAssertTrue(waitForDisappearance(of: dismissRegion, timeout: 5), "Wheel popover did not dismiss")

        let valueAfter = capsule.value as? String
        XCTAssertNotEqual(valueBefore, valueAfter, "Capsule text did not change after adjusting the wheel")
        XCTAssertTrue(valueAfter?.contains("37") == true, "Capsule does not show the picked minute (got \(valueAfter ?? "nil"))")
    }

    @MainActor
    func testAddedRowsAreRevealedAboveKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-datePickerRepro"]
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
        Thread.sleep(forTimeInterval: 1.0) // reveal scroll is delayed 0.4s + animation

        let nameField = app.textFields.matching(identifier: "Name").allElementsBoundByIndex.last!
        XCTAssertTrue(nameField.exists, "No new ingredient name field")
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
        Thread.sleep(forTimeInterval: 1.2) // both reveal passes

        let actionField = app.textFields.matching(identifier: "Action (e.g., Mix, fold, shape)").allElementsBoundByIndex.last!
        XCTAssertTrue(actionField.exists, "No new step action field")
        XCTAssertTrue(actionField.isHittable, "New step action field is not visible")
        XCTAssertLessThan(actionField.frame.maxY, keyboard.frame.minY, "New step action field is under the keyboard")
        app.typeText("Fold")
        XCTAssertEqual(actionField.value as? String, "Fold", "Typing did not land in the new step's Action field")
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
