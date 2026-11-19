import XCTest
import StoreKitTest

final class KeyvowUITests: XCTestCase {
    private var app: XCUIApplication!
    private var storeKitSession: SKTestSession?

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        // Start a local StoreKit test session BEFORE the app launches so
        // product lookups resolve against KeyvowPro.storekit instead of the
        // live App Store, which has no published product in a fresh sandbox.
        // The scheme-level StoreKit reference is not applied by xcodebuild
        // test, so the session has to be created here.
        if let session = Self.makeStoreKitSession() {
            session.resetToDefaultState()
            session.disableDialogs = true
            session.clearTransactions()
            storeKitSession = session
            print("StoreKit test session ready")
        } else {
            print("WARN: KeyvowPro.storekit was not found in any test bundle")
        }

        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        dismissOnboardingIfPresent()
    }

    /// The first-run guide covers the whole app on a fresh install. Every test
    /// must get past it before touching tabs; a skipped guide persists the flag
    /// so later launches in the same simulator boot are unaffected.
    private func dismissOnboardingIfPresent() {
        let skip = app.buttons["Skip"]
        let today = app.buttons["Today"]
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline {
            if today.exists && today.isHittable {
                return
            }
            if skip.exists && skip.isHittable {
                skip.tap()
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
        storeKitSession = nil
        try super.tearDownWithError()
    }

    /// Locate the StoreKit configuration and open a test session for it.
    /// The workflow passes an absolute path through TEST_RUNNER_KEYVOW_STOREKIT;
    /// bundle lookups stay as a fallback for local runs from Xcode.
    private static func makeStoreKitSession() -> SKTestSession? {
        var candidates: [URL] = []
        if let path = ProcessInfo.processInfo.environment["KEYVOW_STOREKIT"], !path.isEmpty {
            candidates.append(URL(fileURLWithPath: path))
        }
        // GitHub-hosted macOS runners check the repository out at a fixed path.
        // Simulator processes can read host files, so this works even when the
        // configuration is not copied into the test bundle.
        candidates.append(URL(fileURLWithPath: "/Users/runner/work/held-ios/held-ios/Keyvow.storekit"))
        for bundle in [Bundle(for: KeyvowUITests.self), Bundle.main] {
            if let url = bundle.url(forResource: "KeyvowPro", withExtension: "storekit") {
                candidates.append(url)
            }
        }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            print("StoreKit config resolved at: \(url.path)")
            if let session = try? SKTestSession(contentsOf: url) {
                return session
            }
            print("WARN: SKTestSession could not be created from \(url.path)")
        }
        print("WARN: candidates checked: \(candidates.map(\.path))")
        return nil
    }

    func testEnglishScreenshotsAndLanguageSwitch() {
        let startupAlert = app.alerts.firstMatch
        if startupAlert.waitForExistence(timeout: 2) {
            attachScreenshot(named: "00-startup-alert")
            let messages = startupAlert.staticTexts.allElementsBoundByIndex
                .map(\.label)
                .joined(separator: " | ")
            XCTFail("A startup alert blocked the main interface: \(messages)")
        }

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
        requireSelectedTab("设置")
        attachScreenshot(named: "06-settings-zh-Hans")

        openLanguagePicker(named: "语言")
        chooseLanguageOption("English")
        requireExists(app.staticTexts["Language"], "Switching back to English did not localize Settings")
        requireHittable(languageRow(named: "Language"), "The English language picker did not become ready")
        requireSelectedTab("Settings")
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
        // iPadOS can expose nested buttons with the same label. Select the real
        // hittable candidate while retaining the hittability assertion below.
        let tabs = app.buttons.matching(NSPredicate(format: "label == %@", label))
        requireExists(tabs.firstMatch, "The \(label) tab was not available")

        let candidates = tabs.allElementsBoundByIndex
        let tab = candidates.first(where: { $0.isHittable }) ?? candidates.last
        XCTAssertNotNil(tab, "The \(label) tab had no accessibility candidates")

        if let tab {
            requireHittable(tab, "The \(label) tab was not available")
            tab.tap()
        }
    }

    private func requireSelectedTab(_ label: String) {
        let selectedTab = app.buttons
            .matching(NSPredicate(format: "label == %@", label))
            .matching(NSPredicate(format: "selected == true"))
            .firstMatch
        requireExists(selectedTab, "The selected tab did not switch to \(label)")
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

    /// Drag a controlled distance so the upgrade card stays framed instead of
    /// jumping a full screen per swipe.
    private func scrollContentUp() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
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

    /// Captures the real in-app purchase page. A local SKTestSession drives
    /// StoreKit so the product (held.pro, $19.99) resolves and the UI renders
    /// its localized price; without a session the test skips.
    func testProUpgradeScreenshot() throws {
        // Without a local StoreKit session the upgrade card can only render the
        // "not available" error, so skip instead of failing the whole job. The
        // screenshot is captured from Xcode on a Mac when CI cannot provide one.
        try XCTSkipIf(
            storeKitSession == nil,
            "No local StoreKit session in this environment; capture the Pro screenshot from Xcode on a Mac"
        )

        selectTab("Settings")
        requireExists(app.navigationBars["Settings"], "Settings did not open")

        let proTitle = app.staticTexts["Keyvow Pro"]
        for _ in 0..<8 where !proTitle.isHittable {
            scrollContentUp()
        }
        requireExists(proTitle, "The Keyvow Pro section was not found")

        // Bring the purchase control into view first: SwiftUI builds lazily, so
        // an off-screen button can never satisfy the label predicate.
        let anyProButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Keyvow Pro"))
            .firstMatch
        for _ in 0..<6 where !anyProButton.isHittable {
            scrollContentUp()
        }

        let loadButton = app.buttons["Load Keyvow Pro"]
        if loadButton.exists && loadButton.isHittable {
            loadButton.tap()
        }

        let priceButton = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Get Keyvow Pro"))
            .firstMatch
        let priceAppeared = priceButton.waitForExistence(timeout: 25)
        // Capture the state either way so a failing run still shows what the
        // upgrade page rendered.
        attachScreenshot(named: "07-pro-upgrade")
        XCTAssertTrue(priceAppeared, "The Pro price never loaded from StoreKit")

        for _ in 0..<4 where !priceButton.isHittable {
            scrollContentUp()
        }
        requireHittable(priceButton, "The Pro purchase button could not be reached")
    }
}
