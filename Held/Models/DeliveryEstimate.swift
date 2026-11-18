import Foundation

/// Stable persisted values. User-facing labels live separately from raw values.
enum EstimatePrecision: String, CaseIterable, Codable {
    case day
    case month
    case quarter
    case season
    case unknown

    var displayLabel: String {
        switch self {
        case .day: return "Exact day or date range"
        case .month: return "Month"
        case .quarter: return "Quarter"
        case .season: return "Season"
        case .unknown: return "Unknown"
        }
    }
}

struct DeliveryEstimateRange: Equatable {
    var start: Date?
    var end: Date?

    var isChronological: Bool {
        guard let start, let end else { return true }
        return start <= end
    }
}

/// Shared input, presentation, and attention rules for imprecise delivery promises.
/// Boundaries are stored for reminders, while display keeps month, quarter, and
/// season semantics instead of presenting a boundary as a promised exact day.
enum DeliveryEstimate {
    static func resolve(
        precision: EstimatePrecision,
        start: Date? = nil,
        end: Date? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> DeliveryEstimateRange {
        switch precision {
        case .unknown:
            return DeliveryEstimateRange(start: nil, end: nil)
        case .day:
            return DeliveryEstimateRange(
                start: start.map { calendar.startOfDay(for: $0) },
                end: end.map { calendar.startOfDay(for: $0) }
            )
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: referenceDate),
                  let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) else {
                return DeliveryEstimateRange(start: nil, end: nil)
            }
            return DeliveryEstimateRange(
                start: calendar.startOfDay(for: interval.start),
                end: calendar.startOfDay(for: lastDay)
            )
        case .quarter:
            let year = calendar.component(.year, from: referenceDate)
            let month = calendar.component(.month, from: referenceDate)
            let firstMonth = ((max(1, month) - 1) / 3) * 3 + 1
            guard let rangeStart = calendar.date(from: DateComponents(year: year, month: firstMonth, day: 1)),
                  let nextQuarter = calendar.date(byAdding: .month, value: 3, to: rangeStart),
                  let lastDay = calendar.date(byAdding: .day, value: -1, to: nextQuarter) else {
                return DeliveryEstimateRange(start: nil, end: nil)
            }
            return DeliveryEstimateRange(
                start: calendar.startOfDay(for: rangeStart),
                end: calendar.startOfDay(for: lastDay)
            )
        case .season:
            let year = calendar.component(.year, from: referenceDate)
            let month = calendar.component(.month, from: referenceDate)
            let startComponents: DateComponents
            let monthsToAdd: Int
            switch month {
            case 12, 1, 2:
                startComponents = DateComponents(year: month == 12 ? year : year - 1, month: 12, day: 1)
                monthsToAdd = 3
            case 3...5:
                startComponents = DateComponents(year: year, month: 3, day: 1)
                monthsToAdd = 3
            case 6...8:
                startComponents = DateComponents(year: year, month: 6, day: 1)
                monthsToAdd = 3
            default:
                startComponents = DateComponents(year: year, month: 9, day: 1)
                monthsToAdd = 3
            }
            guard let rangeStart = calendar.date(from: startComponents),
                  let nextSeason = calendar.date(byAdding: .month, value: monthsToAdd, to: rangeStart),
                  let lastDay = calendar.date(byAdding: .day, value: -1, to: nextSeason) else {
                return DeliveryEstimateRange(start: nil, end: nil)
            }
            return DeliveryEstimateRange(
                start: calendar.startOfDay(for: rangeStart),
                end: calendar.startOfDay(for: lastDay)
            )
        }
    }

    static func displayText(
        precision: EstimatePrecision,
        start: Date?,
        end: Date?,
        calendar: Calendar = .current
    ) -> String {
        switch precision {
        case .unknown:
            return "Unknown"
        case .day:
            if let start, let end {
                if calendar.isDate(start, inSameDayAs: end) {
                    return formatDate(start)
                }
                return "\(formatDate(start)) – \(formatDate(end))"
            }
            if let start { return "From \(formatDate(start))" }
            if let end { return "By \(formatDate(end))" }
            return "Not set"
        case .month:
            guard let start else { return "Month not set" }
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = DateFormatter.dateFormat(
                fromTemplate: "MMMM yyyy",
                options: 0,
                locale: .current
            )
            return formatter.string(from: start)
        case .quarter:
            guard let start else { return "Quarter not set" }
            let month = calendar.component(.month, from: start)
            let quarter = ((max(1, month) - 1) / 3) + 1
            return "Q\(quarter) \(calendar.component(.year, from: start))"
        case .season:
            guard let start else { return "Season not set" }
            let year = calendar.component(.year, from: start)
            switch calendar.component(.month, from: start) {
            case 12: return "Winter \(year)–\(year + 1)"
            case 3: return "Spring \(year)"
            case 6: return "Summer \(year)"
            case 9: return "Autumn \(year)"
            default: return "Season not set"
            }
        }
    }

    static func rangeText(start: Date?, end: Date?) -> String? {
        guard start != nil || end != nil else { return nil }
        let startText = start.map(formatDate) ?? "Unknown"
        let endText = end.map(formatDate) ?? "Unknown"
        return "\(startText) – \(endText)"
    }

    static func hasPassed(
        end: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let end else { return false }
        return calendar.compare(now, to: end, toGranularity: .day) == .orderedDescending
    }
}

extension HeldOrder {
    var estimatePrecision: EstimatePrecision {
        get { EstimatePrecision(rawValue: estimatePrecisionRaw) ?? .unknown }
        set { estimatePrecisionRaw = newValue.rawValue }
    }

    var estimateDisplayText: String {
        DeliveryEstimate.displayText(
            precision: estimatePrecision,
            start: estimateStart,
            end: estimateEnd
        )
    }

    var estimateRangeDisplayText: String? {
        estimatePrecision == .unknown ? nil : DeliveryEstimate.rangeText(start: estimateStart, end: estimateEnd)
    }
}
