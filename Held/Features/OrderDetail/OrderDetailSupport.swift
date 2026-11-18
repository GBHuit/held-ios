import Foundation
import SwiftUI

// MARK: - Navigation and export value types

enum OrderDetailSheet: Identifiable {
    case edit
    case delivery
    case milestone
    case reminder
    case notes
    case evidence(EvidenceDraft)
    case liveText
    case export(OrderExportKind)

    var id: String {
        switch self {
        case .edit: return "edit"
        case .delivery: return "delivery"
        case .milestone: return "milestone"
        case .reminder: return "reminder"
        case .notes: return "notes"
        case .evidence(let draft): return "evidence-\(draft.id.uuidString)"
        case .liveText: return "live-text"
        case .export(let kind): return "export-\(kind.rawValue)"
        }
    }
}

enum OrderExportKind: String, CaseIterable, Identifiable {
    case json
    case csv
    case pdf
    case evidenceZIP

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: return "Order JSON"
        case .csv: return "Order CSV"
        case .pdf: return "Evidence report PDF"
        case .evidenceZIP: return "Evidence ZIP"
        }
    }

    var subtitle: String {
        switch self {
        case .json:
            return "A portable, single-order backup with items, milestones, reminders, notes, and evidence metadata."
        case .csv:
            return "A spreadsheet-compatible summary of this order and its line-item delivery state."
        case .pdf:
            return "A readable evidence report with source details, notes, file sizes, and checksums."
        case .evidenceZIP:
            return "The single-order manifest plus original evidence attachments, verified against their recorded metadata."
        }
    }

    var symbolName: String {
        switch self {
        case .json: return "curlybraces"
        case .csv: return "tablecells"
        case .pdf: return "doc.richtext"
        case .evidenceZIP: return "archivebox"
        }
    }

    var pathExtension: String {
        switch self {
        case .json: return "json"
        case .csv: return "csv"
        case .pdf: return "pdf"
        case .evidenceZIP: return "zip"
        }
    }
}

struct OrderShareItem: Identifiable {
    let id = UUID()
    let url: URL
    let kind: OrderExportKind
}

struct OrderFilePreview: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

// MARK: - Validation

enum OrderDetailValidationError: LocalizedError {
    case required(String)
    case invalidAmount
    case invalidPaymentMethod
    case invalidURL
    case invalidReminderDate
    case incompleteDelivery
    case attachmentStoreUnavailable

    var errorDescription: String? {
        switch self {
        case .required(let field):
            return "\(field) is required."
        case .invalidAmount:
            return "Enter a nonnegative order amount with no more than two decimal places."
        case .invalidPaymentMethod:
            return "For your security, enter only the payment method and optional last four digits. Full card numbers are never saved."
        case .invalidURL:
            return "Enter a complete http or https URL, or leave the URL field empty."
        case .invalidReminderDate:
            return "The reminder’s calculated notification time must be in the future. Adjust the date or lead time."
        case .incompleteDelivery:
            return "Delivered can be selected for an order without line items, or when every noncancelled line item is fully delivered. Update delivery quantities first."
        case .attachmentStoreUnavailable:
            return "Evidence storage is unavailable. Check the storage error on the order screen and try again."
        }
    }
}

enum OrderDetailValidation {
    private static let amountPattern = #"^\+?(?:(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?|\.\d{1,2})$"#

    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func require(_ value: String, field: String) throws -> String {
        let result = trimmed(value)
        guard !result.isEmpty else {
            throw OrderDetailValidationError.required(field)
        }
        return result
    }

    static func optionalText(_ value: String) -> String {
        trimmed(value)
    }

    static func optionalURL(_ value: String) throws -> String {
        let result = trimmed(value)
        guard !result.isEmpty else { return "" }
        guard let url = URL(string: result),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            throw OrderDetailValidationError.invalidURL
        }
        return result
    }

    static func paymentMethod(_ value: String) throws -> String {
        let result = trimmed(value)
        guard !containsFullCardNumber(result) else {
            throw OrderDetailValidationError.invalidPaymentMethod
        }
        return result
    }

    static func minorUnits(from text: String) throws -> Int64 {
        let value = trimmed(text)
        guard value.range(of: amountPattern, options: .regularExpression) != nil else {
            throw OrderDetailValidationError.invalidAmount
        }

        let normalized = value
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "+", with: "")
        guard let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              !amount.isNaN,
              amount >= 0 else {
            throw OrderDetailValidationError.invalidAmount
        }

        var rounded = Decimal()
        var minor = amount * 100
        NSDecimalRound(&rounded, &minor, 0, .plain)
        guard !rounded.isNaN, rounded >= 0, rounded <= Decimal(Int64.max),
              let result = Int64(NSDecimalNumber(decimal: rounded).stringValue) else {
            throw OrderDetailValidationError.invalidAmount
        }
        return result
    }

    static func majorUnits(minor: Int64) -> String {
        NSDecimalNumber(decimal: Decimal(minor) / Decimal(100)).stringValue
    }
}

// MARK: - Presentation helpers

func orderDetailFileSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func orderDetailDateTime(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
}

func orderDetailFilename(for order: HeldOrder, kind: OrderExportKind) -> String {
    let source = OrderDetailValidation.trimmed(order.orderNumber).isEmpty
        ? order.title
        : order.orderNumber
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let cleaned = String(source.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let base = cleaned.isEmpty ? "Order" : cleaned
    return "Held-\(String(base.prefix(80)))-\(UUID().uuidString).\(kind.pathExtension)"
}

struct OrderDetailCallout: View {
    let title: String
    let message: String
    let symbolName: String
    var tone: BadgeTone = .info

    var body: some View {
        HStack(alignment: .top, spacing: HeldSpacing.medium) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(HeldColor.ink)
                Text(message)
                    .heldBody()
                    .foregroundStyle(HeldColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HeldSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var iconColor: Color {
        switch tone {
        case .neutral: return HeldColor.secondaryInk
        case .success, .info: return HeldColor.accent
        case .warning: return HeldColor.amber
        case .danger: return HeldColor.terracotta
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral: return HeldColor.separator.opacity(0.2)
        case .success, .info: return HeldColor.accentSoft.opacity(0.65)
        case .warning: return HeldColor.amberSoft.opacity(0.75)
        case .danger: return HeldColor.terracotta.opacity(0.1)
        }
    }
}

struct OrderDetailMetadataRow: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: HeldSpacing.extraSmall) {
            Text(title)
                .heldCaption()
                .foregroundStyle(HeldColor.secondaryInk)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .body)
                .foregroundStyle(HeldColor.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
