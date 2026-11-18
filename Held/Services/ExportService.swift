import Foundation
import SwiftData
import CryptoKit
import UIKit

// MARK: - Portable snapshot

/// Versioned DTOs keep backups independent of SwiftData's generated schema.
struct HeldBackup: Codable {
    static let currentFormatVersion = 1
    static let applicationIdentifier = "app.held.backup"

    var formatVersion: Int
    var applicationIdentifier: String
    var exportedAt: Date
    var orders: [PortableOrder]
    var settings: PortableSettings
}

struct PortableOrder: Codable {
    var id: String
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
    var items: [PortableOrderItem]
    var milestones: [PortableMilestone]
    var evidence: [PortableEvidence]
    var reminders: [PortableReminder]
}

struct PortableOrderItem: Codable {
    var id: String
    var name: String
    var variant: String
    var quantity: Int
    var deliveredQuantity: Int
    var statusRaw: String
    var amountMinor: Int64?
}

struct PortableMilestone: Codable {
    var id: String
    var kindRaw: String
    var occurredAt: Date
    var title: String
    var note: String
    var sourceURL: String?
}

struct PortableEvidence: Codable {
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
}

struct PortableReminder: Codable {
    var id: String
    var kindRaw: String
    var triggerAt: Date
    var leadDays: Int
    var enabled: Bool
    var label: String
}

struct PortableSettings: Codable {
    var id: String
    var weeklyDigest: Bool
    var remindersEnabled: Bool
    var darkMode: Bool
    var proUnlocked: Bool
    var staleDays: Int
    var leadDays: Int
    var preferredColorSchemeRaw: String
    var lastSelectedTab: Int
}

// Web Held version 1 uses string dates and pre-native field names. These DTOs
// deliberately keep required Web fields non-optional; malformed or incomplete
// payloads must not acquire defaults outside the documented native additions.
private struct WebHeldBackup: Decodable {
    let version: Int
    let exportedAt: String
    let settings: WebHeldSettings
    let orders: [WebHeldOrder]
}

private struct WebHeldSettings: Decodable {
    let weeklyDigest: Bool
    let remindersEnabled: Bool
    let staleDays: Int
    let leadDays: Int
    let darkMode: Bool
}

private struct WebHeldOrder: Decodable {
    let id: String
    let title: String
    let vendor: String
    let orderNumber: String
    let orderedAt: String
    let amountMinor: Int64
    let currencyCode: String
    let paymentMethod: String
    let sourceUrl: String
    let fulfillmentStatus: String
    let resolutionStatus: String
    let estimateText: String
    let estimateEnd: String?
    let nextCheckAt: String?
    let lastUserUpdateAt: String
    let items: [WebHeldOrderItem]
    let milestones: [WebHeldMilestone]
    let evidence: [WebHeldEvidence]
    let reminders: [WebHeldReminder]
    let notes: String?
}

private struct WebHeldOrderItem: Decodable {
    let id: String
    let orderId: String
    let name: String
    let variant: String
    let quantity: Int
    let deliveredQuantity: Int
    let status: String
    let amountMinor: Int64?
}

private struct WebHeldMilestone: Decodable {
    let id: String
    let orderId: String
    let kind: String
    let occurredAt: String
    let title: String
    let note: String
    let sourceUrl: String?
}

private struct WebHeldEvidence: Decodable {
    let id: String
    let orderId: String
    let kind: String
    let title: String
    let filename: String
    let capturedAt: String
    let source: String
    let note: String
    let color: String
}

private struct WebHeldReminder: Decodable {
    let id: String
    let orderId: String
    let kind: String
    let triggerAt: String
    let leadDays: Int
    let enabled: Bool
    let label: String
}

struct RestorePreview {
    /// Keep this value private to the UI's confirmation flow and pass the whole
    /// preview back to `restore`. No model is changed by previewing a backup.
    let backup: HeldBackup
    let orderCount: Int
    let evidenceCount: Int
    let attachmentBytes: Int64
    let exportedAt: Date
    let warnings: [String]
}

enum RestoreMode {
    /// Updates orders with matching IDs and inserts new orders.
    case merge
    /// Deletes existing orders after validation and before the confirmed save.
    case replace
}

struct RestoreResult {
    let insertedOrderCount: Int
    let updatedOrderCount: Int
    let restoredEvidenceCount: Int
}

enum ExportServiceError: LocalizedError {
    case invalidBackup(String)
    case invalidArchive(String)
    case missingAttachment(String)
    case attachmentMismatch(String)
    case archiveRequiresAttachmentStore

    var errorDescription: String? {
        switch self {
        case .invalidBackup(let reason):
            return "This backup is invalid: \(reason)"
        case .invalidArchive(let reason):
            return "This Held archive is invalid: \(reason)"
        case .missingAttachment(let filename):
            return "The attachment “\(filename)” is missing."
        case .attachmentMismatch(let filename):
            return "The attachment “\(filename)” does not match its recorded size or checksum."
        case .archiveRequiresAttachmentStore:
            return "An attachment store is required to restore evidence files."
        }
    }
}

// MARK: - Export and restore

final class ExportService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: JSON

    func makeBackup(orders: [HeldOrder], settings: AppSettings) -> HeldBackup {
        HeldBackup(
            formatVersion: HeldBackup.currentFormatVersion,
            applicationIdentifier: HeldBackup.applicationIdentifier,
            exportedAt: Date(),
            orders: orders.map(Self.portableOrder),
            settings: PortableSettings(
                id: settings.id,
                weeklyDigest: settings.weeklyDigest,
                remindersEnabled: settings.remindersEnabled,
                darkMode: settings.darkMode,
                proUnlocked: settings.proUnlocked,
                staleDays: settings.staleDays,
                leadDays: settings.leadDays,
                preferredColorSchemeRaw: settings.preferredColorSchemeRaw,
                lastSelectedTab: settings.lastSelectedTab
            )
        )
    }

    func encodeJSON(orders: [HeldOrder], settings: AppSettings) throws -> Data {
        try Self.jsonEncoder().encode(makeBackup(orders: orders, settings: settings))
    }

    /// Returns a file URL suitable for ShareLink or UIActivityViewController.
    func writeJSON(orders: [HeldOrder], settings: AppSettings) throws -> URL {
        let data = try encodeJSON(orders: orders, settings: settings)
        let url = temporaryURL(named: "Held-Backup", pathExtension: "json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func previewJSON(_ data: Data) throws -> RestorePreview {
        guard data.count <= 64 * 1_024 * 1_024 else {
            throw ExportServiceError.invalidBackup("The JSON manifest is too large.")
        }

        let backup: HeldBackup
        if let nativeBackup = try? Self.jsonDecoder().decode(HeldBackup.self, from: data) {
            backup = nativeBackup
        } else {
            let webBackup: WebHeldBackup
            do {
                webBackup = try JSONDecoder().decode(WebHeldBackup.self, from: data)
            } catch {
                throw ExportServiceError.invalidBackup(
                    "The JSON could not be decoded as a native or Web Held export."
                )
            }
            backup = try Self.migrateWebBackup(webBackup)
        }

        // Both formats use exactly the same enum, currency, amount, date, ID,
        // path, and settings validation before a preview can reach the UI.
        try Self.validate(backup)
        return Self.preview(for: backup)
    }

    private static func migrateWebBackup(_ web: WebHeldBackup) throws -> HeldBackup {
        HeldBackup(
            formatVersion: web.version,
            applicationIdentifier: HeldBackup.applicationIdentifier,
            exportedAt: try webDate(web.exportedAt),
            orders: try web.orders.map(migrateWebOrder),
            settings: PortableSettings(
                id: "main",
                weeklyDigest: web.settings.weeklyDigest,
                remindersEnabled: web.settings.remindersEnabled,
                darkMode: web.settings.darkMode,
                proUnlocked: false,
                staleDays: web.settings.staleDays,
                leadDays: web.settings.leadDays,
                preferredColorSchemeRaw: "system",
                lastSelectedTab: 0
            )
        )
    }

    private static func migrateWebOrder(_ web: WebHeldOrder) throws -> PortableOrder {
        let childOrderIDs = web.items.map(\.orderId) + web.milestones.map(\.orderId) +
            web.evidence.map(\.orderId) + web.reminders.map(\.orderId)
        guard childOrderIDs.allSatisfy({ $0 == web.id }) else {
            throw ExportServiceError.invalidBackup(
                "A Web child record belongs to a different order."
            )
        }

        let orderedAt = try webDate(web.orderedAt)
        return PortableOrder(
            id: web.id,
            title: web.title,
            vendor: web.vendor,
            orderNumber: web.orderNumber,
            orderedAt: orderedAt,
            amountMinor: web.amountMinor,
            currencyCodeRaw: web.currencyCode,
            paymentMethod: web.paymentMethod,
            sourceURL: web.sourceUrl,
            estimateText: web.estimateText,
            fulfillmentStatusRaw: web.fulfillmentStatus,
            resolutionStatusRaw: web.resolutionStatus,
            estimateEnd: try optionalWebDate(web.estimateEnd),
            nextCheckAt: try optionalWebDate(web.nextCheckAt),
            lastUserUpdateAt: try webDate(web.lastUserUpdateAt),
            notes: web.notes ?? "",
            createdAt: orderedAt,
            trackingNumber: "",
            carrier: "",
            items: web.items.map {
                PortableOrderItem(
                    id: $0.id,
                    name: $0.name,
                    variant: $0.variant,
                    quantity: $0.quantity,
                    deliveredQuantity: $0.deliveredQuantity,
                    statusRaw: $0.status,
                    amountMinor: $0.amountMinor
                )
            },
            milestones: try web.milestones.map {
                PortableMilestone(
                    id: $0.id,
                    kindRaw: $0.kind,
                    occurredAt: try webDate($0.occurredAt),
                    title: $0.title,
                    note: $0.note,
                    sourceURL: $0.sourceUrl
                )
            },
            evidence: try web.evidence.map {
                PortableEvidence(
                    id: $0.id,
                    kindRaw: $0.kind,
                    title: $0.title,
                    filename: $0.filename,
                    capturedAt: try webDate($0.capturedAt),
                    source: $0.source,
                    note: $0.note,
                    colorHex: $0.color,
                    localRelativePath: nil,
                    mimeType: "",
                    fileSize: 0,
                    sha256: nil
                )
            },
            reminders: try web.reminders.map {
                PortableReminder(
                    id: $0.id,
                    kindRaw: $0.kind,
                    triggerAt: try webDate($0.triggerAt),
                    leadDays: $0.leadDays,
                    enabled: $0.enabled,
                    label: $0.label
                )
            }
        )
    }

    private static func optionalWebDate(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        return try webDate(value)
    }

    private static func webDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }
        throw ExportServiceError.invalidBackup(
            "A Web export date is not valid ISO-8601."
        )
    }

    // MARK: ZIP evidence archive

    /// Creates a standards-compliant ZIP using stored (uncompressed) entries.
    /// The archive contains manifest.json and Evidence/<randomized-file>.
    func writeArchive(
        orders: [HeldOrder],
        settings: AppSettings,
        attachmentStore: AttachmentStore
    ) throws -> URL {
        let backup = makeBackup(orders: orders, settings: settings)
        try Self.validate(backup)
        let manifest = try Self.jsonEncoder().encode(backup)
        var entries = [HeldZIPEntry(name: "manifest.json", data: manifest)]
        var addedPaths = Set<String>()

        for order in backup.orders {
            for evidence in order.evidence {
                guard let relativePath = evidence.localRelativePath else { continue }
                let sourceURL = try attachmentStore.url(forRelativePath: relativePath)
                guard fileManager.fileExists(atPath: sourceURL.path) else {
                    throw ExportServiceError.missingAttachment(evidence.filename)
                }
                let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
                try Self.verify(data: data, matches: evidence)
                if addedPaths.insert(relativePath).inserted {
                    entries.append(HeldZIPEntry(name: "Evidence/\(relativePath)", data: data))
                }
            }
        }

        let url = temporaryURL(named: "Held-Evidence-Backup", pathExtension: "zip")
        try HeldZIP.write(entries: entries, to: url)
        return url
    }

    func previewArchive(at archiveURL: URL) throws -> RestorePreview {
        let entries = try readArchiveEntries(at: archiveURL)
        guard let manifest = entries["manifest.json"] else {
            throw ExportServiceError.invalidArchive("manifest.json is missing.")
        }
        let preview = try previewJSON(manifest)
        try Self.validateArchiveEntries(entries, for: preview.backup)
        return preview
    }

    // MARK: Confirmed restore

    /// Restores only after the UI has shown `RestorePreview` and supplied an
    /// explicit mode. JSON restores metadata but clears unavailable local file
    /// references. ZIP restores verify and re-import every referenced file.
    @discardableResult
    func restore(
        _ preview: RestorePreview,
        mode: RestoreMode,
        context: ModelContext,
        attachmentStore: AttachmentStore? = nil,
        archiveURL: URL? = nil
    ) throws -> RestoreResult {
        let backup = preview.backup
        try Self.validate(backup)

        let archiveEntries: [String: Data]?
        if let archiveURL {
            guard attachmentStore != nil else {
                throw ExportServiceError.archiveRequiresAttachmentStore
            }
            let entries = try readArchiveEntries(at: archiveURL)
            try Self.validateArchiveEntries(entries, for: backup)
            archiveEntries = entries
        } else {
            archiveEntries = nil
        }

        // Copy all new evidence before changing SwiftData. If anything fails,
        // these randomized files can be removed without touching old evidence.
        var evidencePathMap: [String: String] = [:]
        var importedPaths: [String] = []
        do {
            if let archiveEntries, let attachmentStore {
                for order in backup.orders {
                    for evidence in order.evidence {
                        guard let relativePath = evidence.localRelativePath else { continue }
                        let entryName = "Evidence/\(relativePath)"
                        guard let data = archiveEntries[entryName] else {
                            throw ExportServiceError.missingAttachment(evidence.filename)
                        }
                        let metadata = try attachmentStore.importData(
                            data,
                            originalFilename: evidence.filename,
                            mimeType: evidence.mimeType
                        )
                        evidencePathMap[evidence.id] = metadata.relativePath
                        importedPaths.append(metadata.relativePath)
                    }
                }
            }

            let existingOrders = try context.fetch(FetchDescriptor<HeldOrder>())
            let existingByID = Dictionary(existingOrders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let existingSettings = try context.fetch(FetchDescriptor<AppSettings>())
            var oldAttachmentCandidates = Set<String>()
            var inserted = 0
            var updated = 0

            if mode == .replace {
                for order in existingOrders {
                    for evidence in order.evidence {
                        if let path = evidence.localRelativePath { oldAttachmentCandidates.insert(path) }
                    }
                    context.delete(order)
                }
            }

            for portable in backup.orders {
                let order: HeldOrder
                if mode == .merge, let existing = existingByID[portable.id] {
                    for evidence in existing.evidence {
                        if let path = evidence.localRelativePath { oldAttachmentCandidates.insert(path) }
                    }
                    order = existing
                    Self.applyScalars(portable, to: existing)
                    Self.replaceChildren(
                        of: existing,
                        with: portable,
                        evidencePathMap: evidencePathMap,
                        includesEvidenceFiles: archiveEntries != nil,
                        context: context
                    )
                    updated += 1
                } else {
                    order = Self.makeOrder(
                        portable,
                        evidencePathMap: evidencePathMap,
                        includesEvidenceFiles: archiveEntries != nil,
                        context: context
                    )
                    context.insert(order)
                    inserted += 1
                }
            }

            let settings = existingSettings.first ?? AppSettings(id: backup.settings.id)
            let verifiedProValue = settings.proUnlocked
            if existingSettings.isEmpty { context.insert(settings) }
            Self.apply(backup.settings, to: settings)
            // A file is not proof of purchase. StoreKit remains authoritative.
            settings.proUnlocked = verifiedProValue
            if mode == .replace && existingSettings.count > 1 {
                for extra in existingSettings.dropFirst() { context.delete(extra) }
            }

            try context.save()

            // Old files are removed only after a successful model save, and only
            // when no remaining evidence record still references them.
            if let attachmentStore, !oldAttachmentCandidates.isEmpty,
               let remainingOrders = try? context.fetch(FetchDescriptor<HeldOrder>()) {
                let remainingPaths = Set(remainingOrders.flatMap { $0.evidence }.compactMap(\.localRelativePath))
                for path in oldAttachmentCandidates where !remainingPaths.contains(path) {
                    try? attachmentStore.remove(relativePath: path)
                }
            }

            return RestoreResult(
                insertedOrderCount: inserted,
                updatedOrderCount: updated,
                restoredEvidenceCount: evidencePathMap.count
            )
        } catch {
            context.rollback()
            if let attachmentStore {
                for path in importedPaths { try? attachmentStore.remove(relativePath: path) }
            }
            throw error
        }
    }

    // MARK: CSV

    func writeCSV(orders: [HeldOrder]) throws -> URL {
        let headers = [
            "ID", "Title", "Vendor", "Order number", "Ordered at", "Amount minor",
            "Currency", "Payment method", "Source URL", "Estimate", "Estimate end",
            "Next check", "Last user update", "Fulfillment", "Resolution", "Notes",
            "Created at", "Tracking number", "Carrier", "Items"
        ]
        var rows = [headers]
        for order in orders {
            let items = order.items.map { item in
                "\(item.name) (\(item.deliveredQuantity)/\(item.quantity), \(item.statusRaw))"
            }.joined(separator: "; ")
            rows.append([
                order.id, order.title, order.vendor, order.orderNumber,
                Self.isoDate(order.orderedAt), String(order.amountMinor), order.currencyCodeRaw,
                order.paymentMethod, order.sourceURL, order.estimateText,
                order.estimateEnd.map(Self.isoDate) ?? "",
                order.nextCheckAt.map(Self.isoDate) ?? "",
                Self.isoDate(order.lastUserUpdateAt), order.fulfillmentStatusRaw,
                order.resolutionStatusRaw, order.notes, Self.isoDate(order.createdAt),
                order.trackingNumber, order.carrier, items
            ])
        }
        // BOM improves spreadsheet compatibility. Every field is quoted and
        // formula-like text is prefixed with an apostrophe before quoting.
        let csv = "\u{FEFF}" + rows.map { row in
            row.map(Self.csvField).joined(separator: ",")
        }.joined(separator: "\r\n")
        let url = temporaryURL(named: "Held-Orders", pathExtension: "csv")
        try Data(csv.utf8).write(to: url, options: .atomic)
        return url
    }

    static func csvField(_ value: String) -> String {
        var safe = value
        let firstNonWhitespace = safe.unicodeScalars.first {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        let startsAsFormula = firstNonWhitespace.map { "=+-@".unicodeScalars.contains($0) } ?? false
        if startsAsFormula || safe.first == "\t" || safe.first == "\r" {
            safe = "'" + safe
        }
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: PDF evidence report

    /// Returns a paginated PDF URL suitable for ShareLink. The report includes
    /// evidence metadata and checksums; original attachments remain in the ZIP.
    func writeEvidenceReport(orders: [HeldOrder]) throws -> URL {
        let url = temporaryURL(named: "Held-Evidence-Report", pathExtension: "pdf")
        try HeldEvidencePDFWriter.write(orders: orders, to: url)
        return url
    }

    // MARK: Model conversion

    private static func portableOrder(_ order: HeldOrder) -> PortableOrder {
        PortableOrder(
            id: order.id,
            title: order.title,
            vendor: order.vendor,
            orderNumber: order.orderNumber,
            orderedAt: order.orderedAt,
            amountMinor: order.amountMinor,
            currencyCodeRaw: order.currencyCodeRaw,
            paymentMethod: order.paymentMethod,
            sourceURL: order.sourceURL,
            estimateText: order.estimateText,
            fulfillmentStatusRaw: order.fulfillmentStatusRaw,
            resolutionStatusRaw: order.resolutionStatusRaw,
            estimateEnd: order.estimateEnd,
            nextCheckAt: order.nextCheckAt,
            lastUserUpdateAt: order.lastUserUpdateAt,
            notes: order.notes,
            createdAt: order.createdAt,
            trackingNumber: order.trackingNumber,
            carrier: order.carrier,
            items: order.items.map {
                PortableOrderItem(
                    id: $0.id, name: $0.name, variant: $0.variant,
                    quantity: $0.quantity, deliveredQuantity: $0.deliveredQuantity,
                    statusRaw: $0.statusRaw, amountMinor: $0.amountMinor
                )
            },
            milestones: order.milestones.map {
                PortableMilestone(
                    id: $0.id, kindRaw: $0.kindRaw, occurredAt: $0.occurredAt,
                    title: $0.title, note: $0.note, sourceURL: $0.sourceURL
                )
            },
            evidence: order.evidence.map {
                PortableEvidence(
                    id: $0.id, kindRaw: $0.kindRaw, title: $0.title,
                    filename: $0.filename, capturedAt: $0.capturedAt, source: $0.source,
                    note: $0.note, colorHex: $0.colorHex,
                    localRelativePath: $0.localRelativePath, mimeType: $0.mimeType,
                    fileSize: $0.fileSize, sha256: $0.sha256
                )
            },
            reminders: order.reminders.map {
                PortableReminder(
                    id: $0.id, kindRaw: $0.kindRaw, triggerAt: $0.triggerAt,
                    leadDays: $0.leadDays, enabled: $0.enabled, label: $0.label
                )
            }
        )
    }

    private static func makeOrder(
        _ portable: PortableOrder,
        evidencePathMap: [String: String],
        includesEvidenceFiles: Bool,
        context: ModelContext
    ) -> HeldOrder {
        let order = HeldOrder(
            id: portable.id,
            title: portable.title,
            vendor: portable.vendor,
            orderNumber: portable.orderNumber,
            orderedAt: portable.orderedAt,
            amountMinor: portable.amountMinor,
            currencyCode: CurrencyCode(rawValue: portable.currencyCodeRaw)!,
            paymentMethod: portable.paymentMethod,
            sourceURL: portable.sourceURL,
            estimateText: portable.estimateText,
            fulfillmentStatus: FulfillmentStatus(rawValue: portable.fulfillmentStatusRaw)!,
            resolutionStatus: ResolutionStatus(rawValue: portable.resolutionStatusRaw)!,
            estimateEnd: portable.estimateEnd,
            nextCheckAt: portable.nextCheckAt,
            lastUserUpdateAt: portable.lastUserUpdateAt,
            notes: portable.notes,
            createdAt: portable.createdAt,
            trackingNumber: portable.trackingNumber,
            carrier: portable.carrier
        )
        order.items = portable.items.map {
            OrderItem(
                id: $0.id, name: $0.name, variant: $0.variant, quantity: $0.quantity,
                deliveredQuantity: $0.deliveredQuantity,
                status: ItemStatus(rawValue: $0.statusRaw)!,
                amountMinor: $0.amountMinor, order: order
            )
        }
        order.milestones = portable.milestones.map {
            Milestone(
                id: $0.id, kind: MilestoneKind(rawValue: $0.kindRaw)!,
                occurredAt: $0.occurredAt, title: $0.title, note: $0.note,
                sourceURL: $0.sourceURL, order: order
            )
        }
        order.evidence = portable.evidence.map {
            makeEvidence(
                $0, order: order, evidencePathMap: evidencePathMap,
                includesEvidenceFiles: includesEvidenceFiles
            )
        }
        order.reminders = portable.reminders.map {
            HeldReminder(
                id: $0.id, kind: ReminderKind(rawValue: $0.kindRaw)!,
                triggerAt: $0.triggerAt, leadDays: $0.leadDays,
                enabled: $0.enabled, label: $0.label, order: order
            )
        }
        // Explicit insertion is required when children are added to an already
        // tracked order during a merge; it is also safe for a new order graph.
        for item in order.items { context.insert(item) }
        for milestone in order.milestones { context.insert(milestone) }
        for evidence in order.evidence { context.insert(evidence) }
        for reminder in order.reminders { context.insert(reminder) }
        return order
    }

    private static func applyScalars(_ portable: PortableOrder, to order: HeldOrder) {
        order.title = portable.title
        order.vendor = portable.vendor
        order.orderNumber = portable.orderNumber
        order.orderedAt = portable.orderedAt
        order.amountMinor = portable.amountMinor
        order.currencyCodeRaw = portable.currencyCodeRaw
        order.paymentMethod = portable.paymentMethod
        order.sourceURL = portable.sourceURL
        order.estimateText = portable.estimateText
        order.fulfillmentStatusRaw = portable.fulfillmentStatusRaw
        order.resolutionStatusRaw = portable.resolutionStatusRaw
        order.estimateEnd = portable.estimateEnd
        order.nextCheckAt = portable.nextCheckAt
        order.lastUserUpdateAt = portable.lastUserUpdateAt
        order.notes = portable.notes
        order.createdAt = portable.createdAt
        order.trackingNumber = portable.trackingNumber
        order.carrier = portable.carrier
    }

    private static func replaceChildren(
        of order: HeldOrder,
        with portable: PortableOrder,
        evidencePathMap: [String: String],
        includesEvidenceFiles: Bool,
        context: ModelContext
    ) {
        for item in order.items { context.delete(item) }
        for milestone in order.milestones { context.delete(milestone) }
        for evidence in order.evidence { context.delete(evidence) }
        for reminder in order.reminders { context.delete(reminder) }
        order.items = []
        order.milestones = []
        order.evidence = []
        order.reminders = []

        order.items = portable.items.map {
            OrderItem(
                id: $0.id, name: $0.name, variant: $0.variant, quantity: $0.quantity,
                deliveredQuantity: $0.deliveredQuantity,
                status: ItemStatus(rawValue: $0.statusRaw)!,
                amountMinor: $0.amountMinor, order: order
            )
        }
        order.milestones = portable.milestones.map {
            Milestone(
                id: $0.id, kind: MilestoneKind(rawValue: $0.kindRaw)!,
                occurredAt: $0.occurredAt, title: $0.title, note: $0.note,
                sourceURL: $0.sourceURL, order: order
            )
        }
        order.evidence = portable.evidence.map {
            makeEvidence(
                $0, order: order, evidencePathMap: evidencePathMap,
                includesEvidenceFiles: includesEvidenceFiles
            )
        }
        order.reminders = portable.reminders.map {
            HeldReminder(
                id: $0.id, kind: ReminderKind(rawValue: $0.kindRaw)!,
                triggerAt: $0.triggerAt, leadDays: $0.leadDays,
                enabled: $0.enabled, label: $0.label, order: order
            )
        }
        // Explicit insertion is required when children are added to an already
        // tracked order during a merge; it is also safe for a new order graph.
        for item in order.items { context.insert(item) }
        for milestone in order.milestones { context.insert(milestone) }
        for evidence in order.evidence { context.insert(evidence) }
        for reminder in order.reminders { context.insert(reminder) }
    }

    private static func makeEvidence(
        _ portable: PortableEvidence,
        order: HeldOrder,
        evidencePathMap: [String: String],
        includesEvidenceFiles: Bool
    ) -> Evidence {
        let restoredPath = includesEvidenceFiles ? evidencePathMap[portable.id] : nil
        return Evidence(
            id: portable.id,
            kind: EvidenceKind(rawValue: portable.kindRaw)!,
            title: portable.title,
            filename: portable.filename,
            capturedAt: portable.capturedAt,
            source: portable.source,
            note: portable.note,
            colorHex: portable.colorHex,
            localRelativePath: restoredPath,
            mimeType: portable.mimeType,
            fileSize: portable.fileSize,
            sha256: portable.sha256,
            order: order
        )
    }

    private static func apply(_ portable: PortableSettings, to settings: AppSettings) {
        settings.weeklyDigest = portable.weeklyDigest
        settings.remindersEnabled = portable.remindersEnabled
        settings.darkMode = portable.darkMode
        settings.staleDays = portable.staleDays
        settings.leadDays = portable.leadDays
        settings.preferredColorSchemeRaw = portable.preferredColorSchemeRaw
        settings.lastSelectedTab = portable.lastSelectedTab
    }

    // MARK: Validation

    private static func preview(for backup: HeldBackup) -> RestorePreview {
        let evidence = backup.orders.flatMap(\.evidence)
        return RestorePreview(
            backup: backup,
            orderCount: backup.orders.count,
            evidenceCount: evidence.count,
            attachmentBytes: evidence.reduce(0) { $0 + $1.fileSize },
            exportedAt: backup.exportedAt,
            warnings: [
                "Pro access is not restored from a file. StoreKit must verify the purchase.",
                "Review the backup before choosing Merge or Replace. Replace deletes existing orders after confirmation."
            ]
        )
    }

    private static func validate(_ backup: HeldBackup) throws {
        guard backup.formatVersion == HeldBackup.currentFormatVersion else {
            throw ExportServiceError.invalidBackup("The format version is not supported.")
        }
        guard backup.applicationIdentifier == HeldBackup.applicationIdentifier else {
            throw ExportServiceError.invalidBackup("The file is not a Held backup.")
        }
        guard backup.orders.count <= 20_000, isFinite(backup.exportedAt) else {
            throw ExportServiceError.invalidBackup("The order count or export date is invalid.")
        }
        try validateSettings(backup.settings)

        var orderIDs = Set<String>()
        var itemIDs = Set<String>()
        var milestoneIDs = Set<String>()
        var evidenceIDs = Set<String>()
        var reminderIDs = Set<String>()

        for order in backup.orders {
            try require(orderIDs.insert(order.id).inserted && validID(order.id), "Duplicate or empty order ID.")
            try require(validText(order.title, max: 500, allowEmpty: false), "An order title is empty or too long.")
            try require(validText(order.vendor, max: 500), "A vendor name is too long.")
            try require(validText(order.orderNumber, max: 300), "An order number is too long.")
            try require(CurrencyCode(rawValue: order.currencyCodeRaw) != nil, "An order has an unsupported currency.")
            try require(FulfillmentStatus(rawValue: order.fulfillmentStatusRaw) != nil, "An order has an unsupported fulfillment status.")
            try require(ResolutionStatus(rawValue: order.resolutionStatusRaw) != nil, "An order has an unsupported resolution status.")
            try require(order.amountMinor >= 0, "An order amount is negative.")
            try require(isFinite(order.orderedAt) && isFinite(order.createdAt) && isFinite(order.lastUserUpdateAt), "An order date is invalid.")
            try require(order.estimateEnd.map(isFinite) ?? true, "An estimate date is invalid.")
            try require(order.nextCheckAt.map(isFinite) ?? true, "A check-in date is invalid.")
            try require(validURL(order.sourceURL), "An order source URL is invalid.")
            try require([order.paymentMethod, order.estimateText, order.trackingNumber, order.carrier].allSatisfy { validText($0, max: 2_000) }, "An order field is too long.")
            try require(validText(order.notes, max: 200_000), "Order notes are too long.")

            for item in order.items {
                try require(itemIDs.insert(item.id).inserted && validID(item.id), "Duplicate or empty item ID.")
                try require(validText(item.name, max: 1_000, allowEmpty: false), "An item name is empty or too long.")
                try require(validText(item.variant, max: 1_000), "An item variant is too long.")
                try require(ItemStatus(rawValue: item.statusRaw) != nil, "An item has an unsupported status.")
                try require(item.quantity >= 0 && item.quantity <= 1_000_000, "An item quantity is invalid.")
                try require(item.deliveredQuantity >= 0 && item.deliveredQuantity <= item.quantity, "A delivered quantity is invalid.")
                try require(item.amountMinor.map { $0 >= 0 } ?? true, "An item amount is negative.")
            }
            for milestone in order.milestones {
                try require(milestoneIDs.insert(milestone.id).inserted && validID(milestone.id), "Duplicate or empty milestone ID.")
                try require(MilestoneKind(rawValue: milestone.kindRaw) != nil, "A milestone has an unsupported kind.")
                try require(isFinite(milestone.occurredAt), "A milestone date is invalid.")
                try require(validText(milestone.title, max: 1_000, allowEmpty: false), "A milestone title is empty or too long.")
                try require(validText(milestone.note, max: 100_000), "A milestone note is too long.")
                try require(milestone.sourceURL.map(validURL) ?? true, "A milestone source URL is invalid.")
            }
            for evidence in order.evidence {
                try require(evidenceIDs.insert(evidence.id).inserted && validID(evidence.id), "Duplicate or empty evidence ID.")
                try require(EvidenceKind(rawValue: evidence.kindRaw) != nil, "Evidence has an unsupported kind.")
                try require(validText(evidence.title, max: 1_000, allowEmpty: false), "An evidence title is empty or too long.")
                try require(validText(evidence.filename, max: 300, allowEmpty: false), "An evidence filename is empty or too long.")
                try require(isFinite(evidence.capturedAt), "An evidence date is invalid.")
                try require(validText(evidence.source, max: 2_000) && validText(evidence.note, max: 100_000), "Evidence text is too long.")
                try require(evidence.colorHex.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil, "Evidence has an invalid color.")
                try require(validText(evidence.mimeType, max: 200), "An evidence MIME type is too long.")
                try require(evidence.fileSize >= 0 && evidence.fileSize <= AttachmentStore.maximumAttachmentBytes, "An evidence file size is invalid.")
                if let path = evidence.localRelativePath {
                    try require(AttachmentStore.isSafeRelativePath(path), "An evidence path is unsafe.")
                }
                if let sha256 = evidence.sha256, !sha256.isEmpty {
                    try require(sha256.range(of: #"^[0-9A-Fa-f]{64}$"#, options: .regularExpression) != nil, "An evidence checksum is invalid.")
                }
            }
            for reminder in order.reminders {
                try require(reminderIDs.insert(reminder.id).inserted && validID(reminder.id), "Duplicate or empty reminder ID.")
                try require(ReminderKind(rawValue: reminder.kindRaw) != nil, "A reminder has an unsupported kind.")
                try require(isFinite(reminder.triggerAt), "A reminder date is invalid.")
                try require(reminder.leadDays >= 0 && reminder.leadDays <= 365, "A reminder lead time is invalid.")
                try require(validText(reminder.label, max: 500, allowEmpty: false), "A reminder label is empty or too long.")
            }
        }
    }

    private static func validateSettings(_ settings: PortableSettings) throws {
        try require(validID(settings.id), "The settings ID is invalid.")
        try require(settings.staleDays >= 0 && settings.staleDays <= 3_650, "The stale-day setting is invalid.")
        try require(settings.leadDays >= 0 && settings.leadDays <= 365, "The default lead time is invalid.")
        try require(["system", "light", "dark"].contains(settings.preferredColorSchemeRaw), "The appearance setting is invalid.")
        try require(settings.lastSelectedTab >= 0 && settings.lastSelectedTab <= 20, "The selected-tab setting is invalid.")
    }

    private static func validateArchiveEntries(_ entries: [String: Data], for backup: HeldBackup) throws {
        for name in entries.keys {
            try require(name == "manifest.json" || name.hasPrefix("Evidence/"), "The archive contains an unexpected entry.")
        }
        var expectedPaths = Set<String>()
        for order in backup.orders {
            for evidence in order.evidence {
                guard let path = evidence.localRelativePath else { continue }
                expectedPaths.insert(path)
                guard let data = entries["Evidence/\(path)"] else {
                    throw ExportServiceError.missingAttachment(evidence.filename)
                }
                try verify(data: data, matches: evidence)
            }
        }
        for name in entries.keys where name.hasPrefix("Evidence/") {
            try require(expectedPaths.contains(String(name.dropFirst("Evidence/".count))), "The archive contains unreferenced evidence.")
        }
    }

    private static func verify(data: Data, matches evidence: PortableEvidence) throws {
        if evidence.fileSize != Int64(data.count) {
            throw ExportServiceError.attachmentMismatch(evidence.filename)
        }
        if let expectedHash = evidence.sha256, !expectedHash.isEmpty {
            let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if actualHash.caseInsensitiveCompare(expectedHash) != .orderedSame {
                throw ExportServiceError.attachmentMismatch(evidence.filename)
            }
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw ExportServiceError.invalidBackup(message) }
    }

    private static func validID(_ value: String) -> Bool {
        validText(value, max: 200, allowEmpty: false)
    }

    private static func validText(_ value: String, max: Int, allowEmpty: Bool = true) -> Bool {
        (allowEmpty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        value.utf8.count <= max && !value.contains("\0")
    }

    private static func validURL(_ value: String) -> Bool {
        guard !value.isEmpty else { return true }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "https" || scheme == "http") && url.host != nil
    }

    private static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && abs(date.timeIntervalSince1970) < 100_000_000_000
    }

    private static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func readArchiveEntries(at url: URL) throws -> [String: Data] {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }
        return try HeldZIP.readEntries(from: url)
    }

    private func temporaryURL(named name: String, pathExtension: String) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }
}

// MARK: - Minimal stored ZIP reader/writer

private struct HeldZIPEntry {
    let name: String
    let data: Data
}

private enum HeldZIP {
    private static let maximumEntries = 20_000
    private static let maximumExpandedBytes = 1_024 * 1_024 * 1_024

    static func write(entries: [HeldZIPEntry], to destination: URL) throws {
        guard entries.count <= maximumEntries, entries.count <= Int(UInt16.max) else {
            throw ExportServiceError.invalidArchive("There are too many files to export.")
        }
        var output = Data()
        var centralRecords = [Data]()
        var names = Set<String>()

        for entry in entries {
            guard safeEntryName(entry.name), names.insert(entry.name).inserted else {
                throw ExportServiceError.invalidArchive("An export filename is unsafe or duplicated.")
            }
            guard let nameData = entry.name.data(using: .utf8), nameData.count <= Int(UInt16.max) else {
                throw ExportServiceError.invalidArchive("An export filename is too long.")
            }
            guard entry.data.count <= Int(UInt32.max), output.count <= Int(UInt32.max) else {
                throw ExportServiceError.invalidArchive("ZIP64 archives are not supported.")
            }
            let localOffset = UInt32(output.count)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let (dosTime, dosDate) = self.dosDate(Date())

            var local = Data()
            append(UInt32(0x0403_4B50), to: &local)
            append(UInt16(20), to: &local)
            append(UInt16(0x0800), to: &local) // UTF-8 names
            append(UInt16(0), to: &local)      // stored, not compressed
            append(dosTime, to: &local)
            append(dosDate, to: &local)
            append(crc, to: &local)
            append(size, to: &local)
            append(size, to: &local)
            append(UInt16(nameData.count), to: &local)
            append(UInt16(0), to: &local)
            local.append(nameData)
            local.append(entry.data)
            output.append(local)

            var central = Data()
            append(UInt32(0x0201_4B50), to: &central)
            append(UInt16(20), to: &central)
            append(UInt16(20), to: &central)
            append(UInt16(0x0800), to: &central)
            append(UInt16(0), to: &central)
            append(dosTime, to: &central)
            append(dosDate, to: &central)
            append(crc, to: &central)
            append(size, to: &central)
            append(size, to: &central)
            append(UInt16(nameData.count), to: &central)
            append(UInt16(0), to: &central)
            append(UInt16(0), to: &central)
            append(UInt16(0), to: &central)
            append(UInt16(0), to: &central)
            append(UInt32(0), to: &central)
            append(localOffset, to: &central)
            central.append(nameData)
            centralRecords.append(central)
        }

        let centralOffset = output.count
        for record in centralRecords { output.append(record) }
        let centralSize = output.count - centralOffset
        guard centralOffset <= Int(UInt32.max), centralSize <= Int(UInt32.max) else {
            throw ExportServiceError.invalidArchive("ZIP64 archives are not supported.")
        }

        append(UInt32(0x0605_4B50), to: &output)
        append(UInt16(0), to: &output)
        append(UInt16(0), to: &output)
        append(UInt16(entries.count), to: &output)
        append(UInt16(entries.count), to: &output)
        append(UInt32(centralSize), to: &output)
        append(UInt32(centralOffset), to: &output)
        append(UInt16(0), to: &output)
        try output.write(to: destination, options: .atomic)
    }

    static func readEntries(from url: URL) throws -> [String: Data] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 22 else {
            throw ExportServiceError.invalidArchive("The file is not a ZIP archive.")
        }
        let earliest = max(0, data.count - 22 - Int(UInt16.max))
        var eocd: Int?
        var index = data.count - 22
        while index >= earliest {
            if readUInt32(data, at: index) == 0x0605_4B50,
               let commentLength = readUInt16(data, at: index + 20),
               index + 22 + Int(commentLength) == data.count {
                eocd = index
                break
            }
            index -= 1
        }
        guard let eocd,
              let disk = readUInt16(data, at: eocd + 4),
              let centralDisk = readUInt16(data, at: eocd + 6),
              let diskCount = readUInt16(data, at: eocd + 8),
              let entryCount = readUInt16(data, at: eocd + 10),
              let centralSize = readUInt32(data, at: eocd + 12),
              let centralOffset = readUInt32(data, at: eocd + 16) else {
            throw ExportServiceError.invalidArchive("The ZIP directory is missing.")
        }
        guard disk == 0, centralDisk == 0, diskCount == entryCount,
              entryCount != UInt16.max, centralOffset != UInt32.max,
              centralSize != UInt32.max, Int(entryCount) <= maximumEntries else {
            throw ExportServiceError.invalidArchive("Multi-disk and ZIP64 archives are not supported.")
        }
        var cursor = Int(centralOffset)
        let centralEnd = cursor + Int(centralSize)
        guard cursor >= 0, centralEnd <= data.count else {
            throw ExportServiceError.invalidArchive("The ZIP directory is truncated.")
        }

        var result: [String: Data] = [:]
        var expandedBytes = 0
        for _ in 0..<Int(entryCount) {
            guard readUInt32(data, at: cursor) == 0x0201_4B50,
                  let flags = readUInt16(data, at: cursor + 8),
                  let method = readUInt16(data, at: cursor + 10),
                  let expectedCRC = readUInt32(data, at: cursor + 16),
                  let compressedSize = readUInt32(data, at: cursor + 20),
                  let uncompressedSize = readUInt32(data, at: cursor + 24),
                  let nameLength = readUInt16(data, at: cursor + 28),
                  let extraLength = readUInt16(data, at: cursor + 30),
                  let commentLength = readUInt16(data, at: cursor + 32),
                  let localOffset = readUInt32(data, at: cursor + 42) else {
                throw ExportServiceError.invalidArchive("A ZIP directory entry is truncated.")
            }
            guard flags & 0x0001 == 0, flags & 0x0800 != 0, method == 0,
                  compressedSize == uncompressedSize else {
                throw ExportServiceError.invalidArchive("Only unencrypted, uncompressed Held ZIP entries are supported.")
            }
            let nameStart = cursor + 46
            let nameEnd = nameStart + Int(nameLength)
            let nextRecord = nameEnd + Int(extraLength) + Int(commentLength)
            guard nameEnd <= data.count, nextRecord <= data.count,
                  let name = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8),
                  safeEntryName(name), result[name] == nil else {
                throw ExportServiceError.invalidArchive("A ZIP entry name is unsafe or duplicated.")
            }
            expandedBytes += Int(uncompressedSize)
            guard expandedBytes <= maximumExpandedBytes else {
                throw ExportServiceError.invalidArchive("The expanded archive is too large.")
            }

            let local = Int(localOffset)
            guard readUInt32(data, at: local) == 0x0403_4B50,
                  let localNameLength = readUInt16(data, at: local + 26),
                  let localExtraLength = readUInt16(data, at: local + 28) else {
                throw ExportServiceError.invalidArchive("A local ZIP header is invalid.")
            }
            let payloadStart = local + 30 + Int(localNameLength) + Int(localExtraLength)
            let payloadEnd = payloadStart + Int(uncompressedSize)
            guard payloadStart >= 0, payloadEnd <= data.count else {
                throw ExportServiceError.invalidArchive("A ZIP entry is truncated.")
            }
            let payload = data.subdata(in: payloadStart..<payloadEnd)
            guard crc32(payload) == expectedCRC else {
                throw ExportServiceError.invalidArchive("A ZIP entry checksum does not match.")
            }
            result[name] = payload
            cursor = nextRecord
        }
        guard cursor == centralEnd else {
            throw ExportServiceError.invalidArchive("The ZIP directory size does not match its contents.")
        }
        return result
    }

    private static func safeEntryName(_ name: String) -> Bool {
        AttachmentStore.isSafeRelativePath(name) && !name.hasSuffix("/")
    }

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB8_8320 : 0)
        }
        return crc
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            let tableIndex = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[tableIndex] ^ (crc >> 8)
        }
        return ~crc
    }

    private static func dosDate(_ date: Date) -> (UInt16, UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(2107, max(1980, components.year ?? 1980))
        let month = min(12, max(1, components.month ?? 1))
        let day = min(31, max(1, components.day ?? 1))
        let hour = min(23, max(0, components.hour ?? 0))
        let minute = min(59, max(0, components.minute ?? 0))
        let second = min(59, max(0, components.second ?? 0))
        let time = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let date = UInt16(((year - 1980) << 9) | (month << 4) | day)
        return (time, date)
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: [
            UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)
        ])
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }
}

// MARK: - PDF report

private enum HeldEvidencePDFWriter {
    private struct Line {
        let text: String
        let font: UIFont
        let color: UIColor
        let indent: CGFloat
        let spaceAfter: CGFloat
    }

    static func write(orders: [HeldOrder], to url: URL) throws {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 48
        let contentWidth = pageRect.width - margin * 2
        let titleFont = UIFont.boldSystemFont(ofSize: 22)
        let headingFont = UIFont.boldSystemFont(ofSize: 15)
        let bodyFont = UIFont.systemFont(ofSize: 10)
        let smallFont = UIFont.monospacedSystemFont(ofSize: 8, weight: .regular)

        var lines = [Line(text: "Held Evidence Report", font: titleFont, color: .label, indent: 0, spaceAfter: 8)]
        lines.append(Line(
            text: "Generated \(Date().formatted(date: .abbreviated, time: .shortened)) • \(orders.count) orders",
            font: bodyFont, color: .secondaryLabel, indent: 0, spaceAfter: 18
        ))

        for order in orders {
            lines.append(Line(text: order.title, font: headingFont, color: .label, indent: 0, spaceAfter: 3))
            lines.append(Line(
                text: "\(order.vendor) • \(order.orderNumber) • \(order.currencyCodeRaw) \(order.amountMinor) minor units",
                font: bodyFont, color: .secondaryLabel, indent: 0, spaceAfter: 3
            ))
            lines.append(Line(
                text: "Ordered \(order.orderedAt.formatted(date: .abbreviated, time: .shortened)) • \(order.fulfillmentStatusRaw) • \(order.resolutionStatusRaw)",
                font: bodyFont, color: .secondaryLabel, indent: 0, spaceAfter: 8
            ))
            if order.evidence.isEmpty {
                lines.append(Line(text: "No evidence recorded.", font: bodyFont, color: .secondaryLabel, indent: 12, spaceAfter: 14))
            } else {
                for evidence in order.evidence {
                    lines.append(Line(text: evidence.title, font: headingFont, color: .label, indent: 12, spaceAfter: 2))
                    lines.append(Line(
                        text: "\(evidence.kindRaw) • \(evidence.filename) • \(evidence.mimeType)",
                        font: bodyFont, color: .label, indent: 18, spaceAfter: 2
                    ))
                    lines.append(Line(
                        text: "Captured \(evidence.capturedAt.formatted(date: .abbreviated, time: .shortened)) • \(evidence.fileSize) bytes",
                        font: bodyFont, color: .secondaryLabel, indent: 18, spaceAfter: 2
                    ))
                    if !evidence.note.isEmpty {
                        lines.append(Line(text: evidence.note, font: bodyFont, color: .label, indent: 18, spaceAfter: 2))
                    }
                    if let path = evidence.localRelativePath {
                        lines.append(Line(text: "File: \(path)", font: smallFont, color: .secondaryLabel, indent: 18, spaceAfter: 2))
                    } else {
                        lines.append(Line(text: "No local file is attached.", font: bodyFont, color: .secondaryLabel, indent: 18, spaceAfter: 2))
                    }
                    if let sha256 = evidence.sha256, !sha256.isEmpty {
                        lines.append(Line(text: "SHA-256: \(sha256)", font: smallFont, color: .secondaryLabel, indent: 18, spaceAfter: 8))
                    } else {
                        lines.append(Line(text: "SHA-256: Not recorded", font: bodyFont, color: .secondaryLabel, indent: 18, spaceAfter: 8))
                    }
                }
            }
        }

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: url) { context in
            var pageNumber = 0
            var cursorY = margin

            func beginPage() {
                context.beginPage()
                pageNumber += 1
                cursorY = margin
                let footer = "Held • Page \(pageNumber)"
                footer.draw(
                    at: CGPoint(x: margin, y: pageRect.height - margin + 18),
                    withAttributes: [.font: bodyFont, .foregroundColor: UIColor.secondaryLabel]
                )
            }

            beginPage()
            for line in lines {
                let availableWidth = contentWidth - line.indent
                let wrapped = wrap(line.text, font: line.font, width: availableWidth)
                for text in wrapped {
                    let height = max(line.font.lineHeight + 2, 12)
                    if cursorY + height > pageRect.height - margin {
                        beginPage()
                    }
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: line.font, .foregroundColor: line.color
                    ]
                    text.draw(
                        in: CGRect(x: margin + line.indent, y: cursorY, width: availableWidth, height: height),
                        withAttributes: attributes
                    )
                    cursorY += height
                }
                cursorY += line.spaceAfter
            }
        }
    }

    private static func wrap(_ text: String, font: UIFont, width: CGFloat) -> [String] {
        guard !text.isEmpty else { return [" "] }

        func measuredWidth(_ value: String) -> CGFloat {
            (value as NSString).size(withAttributes: [.font: font]).width
        }

        var output = [String]()
        for paragraph in text.components(separatedBy: .newlines) {
            if paragraph.isEmpty {
                output.append(" ")
                continue
            }
            var current = ""
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
                let token = String(word)
                let candidate = current.isEmpty ? token : current + " " + token
                if measuredWidth(candidate) <= width {
                    current = candidate
                    continue
                }
                if !current.isEmpty {
                    output.append(current)
                    current = ""
                }
                if measuredWidth(token) <= width {
                    current = token
                    continue
                }
                // Long URLs and SHA-256 hashes have no spaces. Split them by
                // character so the report never clips attachment metadata.
                for character in token {
                    let candidateChunk = current + String(character)
                    if measuredWidth(candidateChunk) > width && !current.isEmpty {
                        output.append(current)
                        current = String(character)
                    } else {
                        current = candidateChunk
                    }
                }
            }
            output.append(current.isEmpty ? " " : current)
        }
        return output
    }
}
