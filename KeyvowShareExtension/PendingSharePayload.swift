import Foundation

/// Versioned on-disk contract shared with Held/Services/PendingShareStore.swift.
/// Keep keys and date encoding stable so previously queued shares remain readable.
struct PendingSharePayload: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: String
    let createdAt: Date
    let sourceURL: String?
    let sharedText: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id
        case createdAt = "created_at"
        case sourceURL = "source_url"
        case sharedText = "shared_text"
    }

    init(id: String = UUID().uuidString, createdAt: Date = Date(), sourceURL: String?, sharedText: String?) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.createdAt = createdAt
        self.sourceURL = sourceURL
        self.sharedText = sharedText
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

enum PendingShareWriter {
    static let appGroupIdentifier = "group.com.held.groupbuy"

    static func write(_ payload: PendingSharePayload, fileManager: FileManager = .default) throws {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw PendingShareWriterError.appGroupUnavailable
        }
        let inbox = container
            .appendingPathComponent("PendingShares", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        try fileManager.createDirectory(
            at: inbox,
            withIntermediateDirectories: true,
            attributes: [FileAttributeKey.protectionKey: FileProtectionType.completeUnlessOpen]
        )
        let destination = inbox.appendingPathComponent("\(payload.id).json", isDirectory: false)
        try payload.encoded().write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

enum PendingShareWriterError: LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        "Keyvow could not open its shared local inbox. Please try again."
    }
}
