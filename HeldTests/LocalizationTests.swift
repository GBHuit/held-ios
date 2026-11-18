import XCTest
@testable import Held

final class LocalizationTests: XCTestCase {
    private var originalLanguage: AppLanguage!

    override func setUp() {
        super.setUp()
        originalLanguage = LocalizationCenter.shared.language
    }

    override func tearDown() {
        LocalizationCenter.shared.setLanguage(originalLanguage)
        originalLanguage = nil
        super.tearDown()
    }

    func testSimplifiedChineseUpdatesSemanticLabelsWithoutChangingRawValues() {
        LocalizationCenter.shared.setLanguage(.simplifiedChinese)

        XCTAssertEqual(FulfillmentStatus.inProduction.displayLabel, "制作中")
        XCTAssertEqual(EstimatePrecision.quarter.displayLabel, "季度")
        XCTAssertEqual(FulfillmentStatus.inProduction.rawValue, "inProduction")
        XCTAssertEqual(EstimatePrecision.quarter.rawValue, "quarter")
    }

    func testEnglishCanBeSelectedAgainInPlace() {
        LocalizationCenter.shared.setLanguage(.simplifiedChinese)
        LocalizationCenter.shared.setLanguage(.english)

        XCTAssertEqual(FulfillmentStatus.inProduction.displayLabel, "In production")
        XCTAssertEqual(L("Settings"), "Settings")
    }

    func testLegacyPortableSettingsWithoutLanguageDecodeAsSystem() throws {
        let json = """
        {
          "id": "main",
          "weeklyDigest": false,
          "remindersEnabled": false,
          "darkMode": false,
          "proUnlocked": false,
          "staleDays": 21,
          "leadDays": 7,
          "preferredColorSchemeRaw": "system",
          "lastSelectedTab": 0
        }
        """
        let settings = try JSONDecoder().decode(
            PortableSettings.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(settings.preferredLanguageRaw)
        XCTAssertEqual(AppLanguage(rawValueOrSystem: settings.preferredLanguageRaw), .system)
    }

    func testInvalidPersistedLanguageFallsBackToSystem() {
        XCTAssertEqual(AppLanguage(rawValueOrSystem: "not-a-language"), .system)
    }
}
