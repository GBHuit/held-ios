import Foundation

private let heldStatusLabels: [String: String] = [
    "ordered": "Ordered",
    "inProduction": "In production",
    "partiallyShipped": "Partially shipped",
    "shipped": "Shipped",
    "delivered": "Delivered",
    "pending": "Pending",
    "cancelled": "Cancelled",
    "refunded": "Refunded",
    "none": "No resolution",
    "refundRequested": "Refund requested",
    "disputed": "Disputed"
]

/// Matches the Web status-label behavior, including readable unknown raw values.
func statusLabel(_ status: String) -> String {
    if let known = heldStatusLabels[status] {
        return known
    }

    let spacedCamelCase = status
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(
            of: "([a-z])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
    let words = spacedCamelCase
        .replacingOccurrences(
            of: "[_\\-]+",
            with: " ",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

    guard let first = words.first else { return "" }
    return String(first).uppercased() + String(words.dropFirst())
}

/// Converts minor units with Decimal only; no Double conversion is used.
func formatMoney(minor: Int64, currency: String) -> String {
    let value = Decimal(minor) / Decimal(100)
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.numberStyle = .currency
    formatter.currencyCode = currency

    if let formatted = formatter.string(from: NSDecimalNumber(decimal: value)) {
        return formatted
    }

    return "\(NSDecimalNumber(decimal: value).stringValue) \(currency)"
}

func formatMoney(minor: Int64, currency: CurrencyCode) -> String {
    formatMoney(minor: minor, currency: currency.rawValue)
}

/// Web-equivalent short date in UTC, for example "Nov 12, 2026".
func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "MMM d, yyyy"
    return formatter.string(from: date)
}

func iso8601Date(from string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
}

func iso8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}
