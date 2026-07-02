import XCTest

// TEMPORARY: verifies the custom capsule date/time picker is interactive —
// tapping the date capsule opens the calendar popover (not the wheels),
// tapping the time capsule opens the wheel popover, and turning the wheel
// updates the capsule text (both capsules share one Date binding, so
// propagation is proven once).
final class CompactDateTimePickerUITests: XCTestCase {

    @MainActor
    func testDateAndTimeCapsulesAreInteractive() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-datePickerRepro"]
        app.launch()

        // The repro host presents the real BakeEditView sheet after ~1s.
        let addStep = app.buttons["Add Step"]
        XCTAssertTrue(addStep.waitForExistence(timeout: 10), "Edit sheet did not appear")

        // Insert a fresh row — the historically glitchy case.
        addStep.tap()

        // Newest row's capsules are the last Date/Time buttons in the form.
        let dateCapsule = app.buttons.matching(identifier: "Date").allElementsBoundByIndex.last!
        XCTAssertTrue(dateCapsule.exists, "No date capsule found")

        dateCapsule.tap()

        // The graphical calendar popover should be up — and NOT the wheels.
        // (Scope to the popover: the form's Start Date row is also a date picker.)
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        XCTAssertTrue(dismissRegion.waitForExistence(timeout: 5), "No popover appeared on date capsule tap")
        let popoverCalendar = app.popovers.datePickers.firstMatch
        XCTAssertTrue(popoverCalendar.waitForExistence(timeout: 3), "Popover has no date picker")
        XCTAssertEqual(app.pickerWheels.count, 0, "Date capsule opened the wheel popover instead of the calendar")
        // The collapsed-calendar bug renders a ~50pt-tall popover; a usable
        // calendar is a few hundred points tall.
        XCTAssertGreaterThan(app.popovers.firstMatch.frame.height, 200, "Calendar popover is collapsed")

        dismissRegion.tap()
        XCTAssertTrue(waitForDisappearance(of: dismissRegion, timeout: 5), "Calendar popover did not dismiss")

        // Time capsule → wheel popover; turning the wheel must update the text.
        let timeCapsule = app.buttons.matching(identifier: "Time").allElementsBoundByIndex.last!
        XCTAssertTrue(timeCapsule.exists, "No time capsule found")
        let timeBefore = timeCapsule.value as? String

        timeCapsule.tap()

        let minuteWheel = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(minuteWheel.waitForExistence(timeout: 5), "Time wheel popover did not open on tap")
        minuteWheel.adjust(toPickerWheelValue: "37")

        app.otherElements["PopoverDismissRegion"].tap()

        let timeAfter = timeCapsule.value as? String
        XCTAssertNotEqual(timeBefore, timeAfter, "Time capsule text did not change after adjusting the wheel")
        XCTAssertTrue(timeAfter?.contains("37") == true, "Time capsule does not show the picked minute (got \(timeAfter ?? "nil"))")
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
