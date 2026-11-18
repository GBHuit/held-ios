import XCTest
@testable import Held

final class DeliveryEstimateTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func testMonthKeepsWholeMonthBoundaries() {
        let range = DeliveryEstimate.resolve(
            precision: .month,
            referenceDate: date("2026-11-15T12:00:00Z"),
            calendar: calendar
        )
        XCTAssertEqual(range.start, date("2026-11-01T00:00:00Z"))
        XCTAssertEqual(range.end, date("2026-11-30T00:00:00Z"))
    }

    func testQuarterKeepsQuarterBoundaries() {
        let range = DeliveryEstimate.resolve(
            precision: .quarter,
            referenceDate: date("2026-11-15T12:00:00Z"),
            calendar: calendar
        )
        XCTAssertEqual(range.start, date("2026-10-01T00:00:00Z"))
        XCTAssertEqual(range.end, date("2026-12-31T00:00:00Z"))
    }

    func testWinterSeasonCrossesYearBoundary() {
        let range = DeliveryEstimate.resolve(
            precision: .season,
            referenceDate: date("2026-01-15T12:00:00Z"),
            calendar: calendar
        )
        XCTAssertEqual(range.start, date("2025-12-01T00:00:00Z"))
        XCTAssertEqual(range.end, date("2026-02-28T00:00:00Z"))
    }

    func testUnknownEstimateHasNoDatesAndNeverPasses() {
        let range = DeliveryEstimate.resolve(precision: .unknown, calendar: calendar)
        XCTAssertNil(range.start)
        XCTAssertNil(range.end)
        XCTAssertFalse(DeliveryEstimate.hasPassed(end: range.end, calendar: calendar))
    }

    func testEstimatePassesOnlyAfterLocalEndDay() {
        let end = date("2026-11-30T00:00:00Z")
        XCTAssertFalse(DeliveryEstimate.hasPassed(
            end: end,
            now: date("2026-11-30T23:59:00Z"),
            calendar: calendar
        ))
        XCTAssertTrue(DeliveryEstimate.hasPassed(
            end: end,
            now: date("2026-12-01T00:00:00Z"),
            calendar: calendar
        ))
    }

    func testPersistedPrecisionRawValuesRemainStable() {
        XCTAssertEqual(EstimatePrecision.day.rawValue, "day")
        XCTAssertEqual(EstimatePrecision.month.rawValue, "month")
        XCTAssertEqual(EstimatePrecision.quarter.rawValue, "quarter")
        XCTAssertEqual(EstimatePrecision.season.rawValue, "season")
        XCTAssertEqual(EstimatePrecision.unknown.rawValue, "unknown")
    }
}
