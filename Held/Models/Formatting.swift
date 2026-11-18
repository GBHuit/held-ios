import Foundation

private let heldStatusLabelKeys: [String: String] = [
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
/// Known machine values are localized; unknown imported values remain untouched
/// apart from the same readable spacing used by the original app.
func statusLabel(_ status: String) -> String {
    if let key = heldStatusLabelKeys[status] {
        return L(key)
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
    LocalizationCenter.shared.money(minor: minor, currency: currency)
}

func formatMoney(minor: Int64, currency: CurrencyCode) -> String {
    formatMoney(minor: minor, currency: currency.rawValue)
}

/// User-facing dates follow the in-app language and the device's time zone.
/// Export and backup dates continue to use the ISO8601 helpers below.
func formatDate(_ date: Date) -> String {
    LocalizationCenter.shared.date(date)
}

/// Rejects 12–19 digit card numbers, including common space/hyphen grouping.
/// Payment method text should contain only a method name and optional last four.
func containsFullCardNumber(_ text: String) -> Bool {
    let pattern = #"(?<![0-9])(?:[0-9][ -]?){11,18}[0-9](?![0-9])"#
    return text.range(of: pattern, options: .regularExpression) != nil
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
