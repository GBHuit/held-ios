import XCTest

final class KeyvowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
        try super.tearDownWithError()
    }

    func testEnglishScreenshotsAndLanguageSwitch() {
        showEnglishHome()
        requireExists(app.staticTexts["Keyvow"], "The Keyvow home title did not appear")

        // This section only exists after the seeded orders have reached HomeView.
        let seededHomeContent = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Needs attention"))
            .firstMatch
        requireExists(seededHomeContent, "Home did not display the seeded orders")
        attachScreenshot(named: "01-home-en")

        selectTab("Orders")
        requireExists(app.navigationBars["Orders"], "Orders did not open")

        let firstCard = firstOrderCard()
        requireHittable(firstCard, "The first seeded order card was not tappable")
        attachScreenshot(named: "02-orders-en")

        let orderTitle = firstCard.label.components(separatedBy: ", ").first ?? ""
        XCTAssertFalse(orderTitle.isEmpty, "The order card did not expose its title")
        firstCard.tap()

        requireExists(app.navigationBars[orderTitle], "The selected order's detail page did not open")
        requireHittable(app.buttons["Edit"], "The order detail page was not ready")
        attachScreenshot(named: "03-promise-en")

        let titledBackButton = app.navigationBars.buttons["Orders"]
        let backButton = titledBackButton.exists
            ? titledBackButton
            : app.navigationBars.buttons.element(boundBy: 0)
        requireHittable(backButton, "The order detail back button was not available")
        backButton.tap()
        requireExists(app.navigationBars["Orders"], "Returning from the order detail did not restore Orders")
        requireHittable(firstOrderCard(), "The order list was not restored after going back")

        let addButton = app.buttons["Add a new order"].firstMatch
        requireHittable(addButton, "The add-order button was not available")
        addButton.tap()
        requireExists(app.navigationBars["New order"], "The new-order flow did not open")
        requireHittable(app.buttons["Cancel"], "The new-order flow was not ready")
        attachScreenshot(named: "04-capture-en")
        app.buttons["Cancel"].tap()
        requireExists(app.navigationBars["Orders"], "Cancelling the new-order flow did not restore Orders")

        selectTab("Funds")
        requireExists(app.navigationBars["Funds"], "Funds did not open")
        let fundsHeader = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Every currency, kept distinct."))
            .firstMatch
        requireExists(fundsHeader, "Funds did not display the seeded multi-currency ledger")
        attachScreenshot(named: "05-funds-en")

        selectTab("Settings")
        requireExists(app.navigationBars["Settings"], "Settings did not open")
        let settingsIntroduction = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Keyvow, on your terms."))
            .firstMatch
        requireExists(settingsIntroduction, "Settings content did not load")
        attachScreenshot(named: "06-settings-en")

        openLanguagePicker(named: "Language")
        chooseLanguageOption("简体中文")
        requireExists(app.staticTexts["语言"], "Switching to Simplified Chinese did not localize Settings")
        requireHittable(languageRow(named: "语言"), "The Chinese language picker did not become ready")
        XCTAssertTrue(app.buttons["设置"].isSelected, "The selected tab did not switch to Chinese")
        attachScreenshot(named: "06-settings-zh-Hans")

        openLanguagePicker(named: "语言")
        chooseLanguageOption("English")
        requireExists(app.staticTexts["Language"], "Switching back to English did not localize Settings")
        requireHittable(languageRow(named: "Language"), "The English language picker did not become ready")
        XCTAssertTrue(app.buttons["Settings"].isSelected, "The selected tab did not switch back to English")
    }

    private func showEnglishHome() {
        // A previous interrupted run may have persisted Chinese. Restore English
        // through the real UI without clearing orders or other application data.
        if !app.buttons["Today"].waitForExistence(timeout: 5) {
            selectTab("设置")
            requireExists(app.navigationBars["设置"], "Chinese Settings did not open")
            openLanguagePicker(named: "语言")
            chooseLanguageOption("English")
            requireExists(app.staticTexts["Language"], "English could not be restored after launch")
        }

        selectTab("Today")
    }

    private func selectTab(_ label: String) {
        // Both the iPhone tab bar and the iPadOS sidebar expose tab items as buttons.
        let tab = app.buttons[label]
        requireHittable(tab, "The \(label) tab was not available")
        tab.tap()
    }

    private func firstOrderCard() -> XCUIElement {
        // HomeOrderCard exposes one accessibility element whose stable English
        // description ends with its completion percentage. Query order follows
        // the List's NavigationLink order, so index zero is the visible first card.
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "percent complete"))
            .element(boundBy: 0)
    }

    private func languageRow(named label: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", label))
            .firstMatch
    }

    private func openLanguagePicker(named label: String) {
        let row = languageRow(named: label)
        _ = row.waitForExistence(timeout: 2)

        // Form rows can be below the fold on smaller devices. Scrolling is only
        // positioning; the final hittability assertion still proves availability.
        for _ in 0..<4 where !row.isHittable {
            app.swipeUp()
            _ = row.waitForExistence(timeout: 1)
        }

        requireHittable(row, "The \(label) picker could not be reached")
        row.tap()
    }

    private func chooseLanguageOption(_ option: String) {
        // Automatic Form pickers use navigation-link/menu buttons on current iOS
        // versions. The static-text fallback also supports cell-based options.
        let button = app.buttons[option]
        if button.waitForExistence(timeout: 3) {
            requireHittable(button, "The \(option) language option was not tappable")
            button.tap()
            return
        }

        let text = app.staticTexts[option]
        requireHittable(text, "The \(option) language option did not appear")
        text.tap()
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func requireExists(
        _ element: XCUIElement,
        _ message: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message, file: file, line: line)
    }

    private func requireHittable(
        _ element: XCUIElement,
        _ message: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requireExists(element, message, timeout: timeout, file: file, line: line)
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [hittable], timeout: timeout),
            .completed,
            message,
            file: file,
            line: line
        )
    }
}
