import Foundation

struct PendingShare: Identifiable, Equatable {
    let id: String
    let createdAt: Date
    let sourceURL: String
    let sharedText: String

    var suggestedTitle: String {
        if !sharedText.isEmpty {
            return String(sharedText.prefix(240))
        }
        guard let url = URL(string: sourceURL) else { return "" }
        return url.host ?? ""
    }
}

private struct PendingSharePayload: Codable {
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
}

enum PendingShareStoreError: LocalizedError {
    case appGroupUnavailable
    case invalidPayload(String)
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "The shared Keyvow inbox is unavailable. The shared item has not been removed."
        case .invalidPayload(let id):
            return "Shared item \(id) could not be read. It remains in the shared inbox."
        case .unsupportedSchema(let version):
            return "Shared item format version \(version) is not supported by this version of Keyvow. It remains in the shared inbox."
        }
    }
}

/// Reads one pending share at a time. Resolution writes a durable tombstone before
/// deleting the inbox file, preventing a failed deletion from importing it twice.
final class PendingShareStore {
    static let shared = PendingShareStore()

    private static let appGroupIdentifier = "group.com.held.groupbuy"
    private let fileManager: FileManager
    private var resolvedThisLaunch = Set<String>()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func nextPendingShare() throws -> PendingShare? {
        let inbox = try directory(named: "PendingShares", create: false)
        guard fileManager.fileExists(atPath: inbox.path) else { return nil }
        let resolved = try resolvedIdentifiers()
        let files = try fileManager.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for file in files {
            let fileID = file.deletingPathExtension().lastPathComponent
            guard UUID(uuidString: fileID) != nil,
                  !resolved.contains(fileID),
                  !resolvedThisLaunch.contains(fileID) else { continue }
            let payload: PendingSharePayload
            do {
                let data = try Data(contentsOf: file, options: .mappedIfSafe)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                payload = try decoder.decode(PendingSharePayload.self, from: data)
            } catch {
                throw PendingShareStoreError.invalidPayload(fileID)
            }
            guard payload.schemaVersion == 1 else {
                throw PendingShareStoreError.unsupportedSchema(payload.schemaVersion)
            }
            guard payload.id == fileID, UUID(uuidString: payload.id) != nil else {
                throw PendingShareStoreError.invalidPayload(fileID)
            }

            let rawURL = (payload.sourceURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawURL.isEmpty {
                guard let url = URL(string: rawURL),
                      url.scheme?.lowercased() == "https",
                      url.host != nil else {
                    throw PendingShareStoreError.invalidPayload(fileID)
                }
            }
            let text = (payload.sharedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawURL.isEmpty || !text.isEmpty else {
                throw PendingShareStoreError.invalidPayload(fileID)
            }
            return PendingShare(
                id: payload.id,
                createdAt: payload.createdAt,
                sourceURL: rawURL,
                sharedText: text
            )
        }
        return nil
    }

    /// Call only after the order was saved successfully.
    func consumeAfterImport(id: String) {
        resolve(id: id)
    }

    /// Cancelling the new-order flow intentionally discards the pending share.
    func discardAfterCancellation(id: String) {
        resolve(id: id)
    }

    private func resolve(id: String) {
        guard UUID(uuidString: id) != nil else { return }
        resolvedThisLaunch.insert(id)
        if let tombstones = try? directory(named: "ResolvedShareIDs", create: true) {
            let marker = tombstones.appendingPathComponent(id, isDirectory: false)
            try? Data(id.utf8).write(to: marker, options: [.atomic, .completeFileProtectionUnlessOpen])
        }
        if let inbox = try? directory(named: "PendingShares", create: false) {
            let payload = inbox.appendingPathComponent("\(id).json", isDirectory: false)
            try? fileManager.removeItem(at: payload)
        }
    }

    private func resolvedIdentifiers() throws -> Set<String> {
        let directory = try directory(named: "ResolvedShareIDs", create: false)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(atPath: directory.path)
        return Set(files.filter { UUID(uuidString: $0) != nil })
    }

    private func directory(named name: String, create: Bool) throws -> URL {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else {
            throw PendingShareStoreError.appGroupUnavailable
        }
        let directory = container
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        if create {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [FileAttributeKey.protectionKey: FileProtectionType.completeUnlessOpen]
            )
        }
        return directory
    }
}
