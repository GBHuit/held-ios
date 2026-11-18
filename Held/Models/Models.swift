import Foundation
import SwiftData

// MARK: - Enumerations

enum FulfillmentStatus: String, CaseIterable, Codable {
    case ordered
    case inProduction
    case partiallyShipped
    case shipped
    case delivered

    var displayLabel: String {
        switch self {
        case .ordered: return "Ordered"
        case .inProduction: return "In production"
        case .partiallyShipped: return "Partially shipped"
        case .shipped: return "Shipped"
        case .delivered: return "Delivered"
        }
    }

    var symbolName: String {
        switch self {
        case .ordered: return "bag"
        case .inProduction: return "gearshape"
        case .partiallyShipped: return "shippingbox"
        case .shipped: return "paperplane"
        case .delivered: return "checkmark.circle"
        }
    }
}

enum ItemStatus: String, CaseIterable, Codable {
    case pending
    case shipped
    case delivered
    case cancelled
    case refunded

    var displayLabel: String {
        switch self {
        case .pending: return "Pending"
        case .shipped: return "Shipped"
        case .delivered: return "Delivered"
        case .cancelled: return "Cancelled"
        case .refunded: return "Refunded"
        }
    }

    var symbolName: String {
        switch self {
        case .pending: return "clock"
        case .shipped: return "paperplane"
        case .delivered: return "checkmark.circle"
        case .cancelled: return "xmark.circle"
        case .refunded: return "arrow.uturn.backward.circle"
        }
    }
}

enum ResolutionStatus: String, CaseIterable, Codable {
    case none
    case cancelled
    case refundRequested
    case refunded
    case disputed

    var displayLabel: String {
        switch self {
        case .none: return "No resolution"
        case .cancelled: return "Cancelled"
        case .refundRequested: return "Refund requested"
        case .refunded: return "Refunded"
        case .disputed: return "Disputed"
        }
    }

    var symbolName: String {
        switch self {
        case .none: return "minus.circle"
        case .cancelled: return "xmark.circle"
        case .refundRequested: return "arrow.uturn.backward.circle"
        case .refunded: return "checkmark.circle"
        case .disputed: return "exclamationmark.bubble"
        }
    }
}

enum MilestoneKind: String, CaseIterable, Codable {
    case purchase
    case update
    case delay
    case shipment
    case delivery
    case refund
    case dispute

    var displayLabel: String {
        switch self {
        case .purchase: return "Purchase"
        case .update: return "Update"
        case .delay: return "Delay"
        case .shipment: return "Shipment"
        case .delivery: return "Delivery"
        case .refund: return "Refund"
        case .dispute: return "Dispute"
        }
    }

    var symbolName: String {
        switch self {
        case .purchase: return "bag"
        case .update: return "text.bubble"
        case .delay: return "clock.exclamationmark"
        case .shipment: return "shippingbox"
        case .delivery: return "checkmark.circle"
        case .refund: return "arrow.uturn.backward.circle"
        case .dispute: return "exclamationmark.bubble"
        }
    }
}

enum EvidenceKind: String, CaseIterable, Codable {
    case receipt
    case originalListing
    case terms
    case communication
    case shipping

    var displayLabel: String {
        switch self {
        case .receipt: return "Receipt"
        case .originalListing: return "Original listing"
        case .terms: return "Terms"
        case .communication: return "Communication"
        case .shipping: return "Shipping"
        }
    }

    var symbolName: String {
        switch self {
        case .receipt: return "doc.text"
        case .originalListing: return "archivebox"
        case .terms: return "doc.plaintext"
        case .communication: return "envelope"
        case .shipping: return "shippingbox"
        }
    }
}

enum ReminderKind: String, CaseIterable, Codable {
    case checkIn
    case deadline

    var displayLabel: String {
        switch self {
        case .checkIn: return "Check-in"
        case .deadline: return "Deadline"
        }
    }

    var symbolName: String {
        switch self {
        case .checkIn: return "bell"
        case .deadline: return "calendar.badge.exclamationmark"
        }
    }
}

enum AttentionReasonKind: String, CaseIterable, Codable {
    case estimate
    case check
    case deadline
    case stale
    case partial

    var displayLabel: String {
        switch self {
        case .estimate: return "Estimate"
        case .check: return "Check-in"
        case .deadline: return "Deadline"
        case .stale: return "Stale"
        case .partial: return "Partial delivery"
        }
    }

    var symbolName: String {
        switch self {
        case .estimate: return "calendar"
        case .check: return "bell"
        case .deadline: return "calendar.badge.exclamationmark"
        case .stale: return "clock"
        case .partial: return "shippingbox"
        }
    }
}

enum CurrencyCode: String, CaseIterable, Codable {
    case USD
    case GBP
    case EUR
    case CAD
    case AUD

    var displayLabel: String { rawValue }
}

// MARK: - SwiftData models

@Model
final class HeldOrder {
    @Attribute(.unique) var id: String
    var title: String
    var vendor: String
    var orderNumber: String
    var orderedAt: Date
    var amountMinor: Int64
    var currencyCodeRaw: String
    var paymentMethod: String
    var sourceURL: String
    var estimateText: String
    var fulfillmentStatusRaw: String
    var resolutionStatusRaw: String
    var estimateEnd: Date?
    var nextCheckAt: Date?
    var lastUserUpdateAt: Date
    var notes: String
    var createdAt: Date
    var trackingNumber: String
    var carrier: String

    @Relationship(deleteRule: .cascade, inverse: \OrderItem.order)
    var items: [OrderItem] = []

    @Relationship(deleteRule: .cascade, inverse: \Milestone.order)
    var milestones: [Milestone] = []

    @Relationship(deleteRule: .cascade, inverse: \Evidence.order)
    var evidence: [Evidence] = []

    @Relationship(deleteRule: .cascade, inverse: \HeldReminder.order)
    var reminders: [HeldReminder] = []

    var currencyCode: CurrencyCode {
        get { CurrencyCode(rawValue: currencyCodeRaw) ?? .USD }
        set { currencyCodeRaw = newValue.rawValue }
    }

    var fulfillmentStatus: FulfillmentStatus {
        get { FulfillmentStatus(rawValue: fulfillmentStatusRaw) ?? .ordered }
        set { fulfillmentStatusRaw = newValue.rawValue }
    }

    var resolutionStatus: ResolutionStatus {
        get { ResolutionStatus(rawValue: resolutionStatusRaw) ?? .none }
        set { resolutionStatusRaw = newValue.rawValue }
    }

    /// Physical fulfillment and dispute resolution deliberately remain independent.
    var isActive: Bool {
        switch resolutionStatus {
        case .cancelled, .refunded:
            return false
        case .refundRequested, .disputed:
            return true
        case .none:
            return fulfillmentStatus != .delivered
        }
    }

    /// A normalized version of the Web app's 0...100 progress calculation.
    var progress: Double {
        if resolutionStatus == .cancelled { return 0 }
        if fulfillmentStatus == .delivered { return 1 }

        let baseline: Double
        switch fulfillmentStatus {
        case .ordered: baseline = 0.12
        case .inProduction: baseline = 0.32
        case .partiallyShipped: baseline = 0.50
        case .shipped: baseline = 0.78
        case .delivered: baseline = 1
        }

        let totalUnits = items.reduce(0) { $0 + max(0, $1.quantity) }
        guard totalUnits > 0 else { return baseline }

        var weightedUnits = 0.0
        for item in items {
            let quantity = max(0, item.quantity)
            guard quantity > 0 else { continue }

            let recordedDelivered = min(quantity, max(0, item.deliveredQuantity))
            let delivered = item.status == .delivered ? quantity : recordedDelivered
            let inTransit = item.status == .shipped ? max(0, quantity - delivered) : 0
            weightedUnits += Double(delivered) + Double(inTransit) * 0.75
        }

        let itemProgress = weightedUnits / Double(totalUnits)
        let normalized = min(1, max(baseline, itemProgress))
        return (normalized * 100).rounded() / 100
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        vendor: String,
        orderNumber: String,
        orderedAt: Date,
        amountMinor: Int64,
        currencyCode: CurrencyCode = .USD,
        paymentMethod: String = "",
        sourceURL: String = "",
        estimateText: String = "",
        fulfillmentStatus: FulfillmentStatus = .ordered,
        resolutionStatus: ResolutionStatus = .none,
        estimateEnd: Date? = nil,
        nextCheckAt: Date? = nil,
        lastUserUpdateAt: Date? = nil,
        notes: String = "",
        createdAt: Date? = nil,
        trackingNumber: String = "",
        carrier: String = ""
    ) {
        self.id = id
        self.title = title
        self.vendor = vendor
        self.orderNumber = orderNumber
        self.orderedAt = orderedAt
        self.amountMinor = amountMinor
        self.currencyCodeRaw = currencyCode.rawValue
        self.paymentMethod = paymentMethod
        self.sourceURL = sourceURL
        self.estimateText = estimateText
        self.fulfillmentStatusRaw = fulfillmentStatus.rawValue
        self.resolutionStatusRaw = resolutionStatus.rawValue
        self.estimateEnd = estimateEnd
        self.nextCheckAt = nextCheckAt
        self.lastUserUpdateAt = lastUserUpdateAt ?? orderedAt
        self.notes = notes
        self.createdAt = createdAt ?? orderedAt
        self.trackingNumber = trackingNumber
        self.carrier = carrier
    }
}

@Model
final class OrderItem {
    var id: String
    var name: String
    var variant: String
    var quantity: Int
    var deliveredQuantity: Int
    var statusRaw: String
    var amountMinor: Int64?
    var order: HeldOrder?

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        variant: String = "",
        quantity: Int = 1,
        deliveredQuantity: Int = 0,
        status: ItemStatus = .pending,
        amountMinor: Int64? = nil,
        order: HeldOrder? = nil
    ) {
        self.id = id
        self.name = name
        self.variant = variant
        self.quantity = quantity
        self.deliveredQuantity = deliveredQuantity
        self.statusRaw = status.rawValue
        self.amountMinor = amountMinor
        self.order = order
    }
}

@Model
final class Milestone {
    var id: String
    var kindRaw: String
    var occurredAt: Date
    var title: String
    var note: String
    var sourceURL: String?
    var order: HeldOrder?

    var kind: MilestoneKind {
        get { MilestoneKind(rawValue: kindRaw) ?? .update }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        kind: MilestoneKind = .update,
        occurredAt: Date,
        title: String,
        note: String = "",
        sourceURL: String? = nil,
        order: HeldOrder? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.occurredAt = occurredAt
        self.title = title
        self.note = note
        self.sourceURL = sourceURL
        self.order = order
    }
}

@Model
final class Evidence {
    var id: String
    var kindRaw: String
    var title: String
    var filename: String
    var capturedAt: Date
    var source: String
    var note: String
    var colorHex: String
    var localRelativePath: String?
    var mimeType: String
    var fileSize: Int64
    var sha256: String?
    var order: HeldOrder?

    var kind: EvidenceKind {
        get { EvidenceKind(rawValue: kindRaw) ?? .receipt }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        kind: EvidenceKind = .receipt,
        title: String,
        filename: String,
        capturedAt: Date,
        source: String = "",
        note: String = "",
        colorHex: String = "#657C72",
        localRelativePath: String? = nil,
        mimeType: String = "",
        fileSize: Int64 = 0,
        sha256: String? = nil,
        order: HeldOrder? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.filename = filename
        self.capturedAt = capturedAt
        self.source = source
        self.note = note
        self.colorHex = colorHex
        self.localRelativePath = localRelativePath
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.sha256 = sha256
        self.order = order
    }
}

@Model
final class HeldReminder {
    var id: String
    var kindRaw: String
    var triggerAt: Date
    var leadDays: Int
    var enabled: Bool
    var label: String
    var order: HeldOrder?

    var kind: ReminderKind {
        get { ReminderKind(rawValue: kindRaw) ?? .checkIn }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        kind: ReminderKind = .checkIn,
        triggerAt: Date,
        leadDays: Int = 0,
        enabled: Bool = true,
        label: String,
        order: HeldOrder? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.triggerAt = triggerAt
        self.leadDays = leadDays
        self.enabled = enabled
        self.label = label
        self.order = order
    }
}

@Model
final class AppSettings {
    @Attribute(.unique) var id: String
    var weeklyDigest: Bool
    var remindersEnabled: Bool
    var darkMode: Bool
    var proUnlocked: Bool
    var staleDays: Int
    var leadDays: Int
    var preferredColorSchemeRaw: String
    var lastSelectedTab: Int
    var didInstallDebugSeed: Bool = false

    init(
        id: String = "main",
        weeklyDigest: Bool = false,
        remindersEnabled: Bool = false,
        darkMode: Bool = false,
        proUnlocked: Bool = false,
        staleDays: Int = 21,
        leadDays: Int = 7,
        preferredColorSchemeRaw: String = "system",
        lastSelectedTab: Int = 0,
        didInstallDebugSeed: Bool = false
    ) {
        self.id = id
        self.weeklyDigest = weeklyDigest
        self.remindersEnabled = remindersEnabled
        self.darkMode = darkMode
        self.proUnlocked = proUnlocked
        self.staleDays = staleDays
        self.leadDays = leadDays
        self.preferredColorSchemeRaw = preferredColorSchemeRaw
        self.lastSelectedTab = lastSelectedTab
        self.didInstallDebugSeed = didInstallDebugSeed
    }

    /// Fetches or inserts the singleton. The caller remains responsible for saving.
    static func fetchOrCreate(context: ModelContext) throws -> AppSettings {
        let mainID = "main"
        var descriptor = FetchDescriptor<AppSettings>(
            predicate: #Predicate<AppSettings> { settings in
                settings.id == mainID
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let settings = AppSettings(id: mainID)
        context.insert(settings)
        return settings
    }
}

// MARK: - Attention value types

struct OrderFundsBreakdown {
    var totalMinor: Int64
    var pendingMinor: Int64
    var deliveredMinor: Int64
    var refundedMinor: Int64
    var refundPendingMinor: Int64
    var cancelledMinor: Int64
    var usesDeliveryFallback: Bool
}

struct CurrencyFunds {
    var currency: String
    var totalMinor: Int64
    var pendingMinor: Int64
    var deliveredMinor: Int64
    var refundedMinor: Int64
    var refundPendingMinor: Int64
    var cancelledMinor: Int64

    init(
        currency: String,
        totalMinor: Int64 = 0,
        pendingMinor: Int64 = 0,
        deliveredMinor: Int64 = 0,
        refundedMinor: Int64 = 0,
        refundPendingMinor: Int64 = 0,
        cancelledMinor: Int64 = 0
    ) {
        self.currency = currency
        self.totalMinor = totalMinor
        self.pendingMinor = pendingMinor
        self.deliveredMinor = deliveredMinor
        self.refundedMinor = refundedMinor
        self.refundPendingMinor = refundPendingMinor
        self.cancelledMinor = cancelledMinor
    }
}

struct AttentionReason {
    var kind: AttentionReasonKind
    var title: String
    var description: String

    init(kind: AttentionReasonKind, title: String, description: String) {
        self.kind = kind
        self.title = title
        self.description = description
    }
}

struct OrderAttention {
    var order: HeldOrder
    var reasons: [AttentionReason]

    init(order: HeldOrder, reasons: [AttentionReason]) {
        self.order = order
        self.reasons = reasons
    }
}
