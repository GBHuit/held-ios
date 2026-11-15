import Foundation
import CryptoKit
import UniformTypeIdentifiers
import ImageIO
import UIKit

/// Metadata suitable for copying into an Evidence model. Files remain on disk,
/// outside SwiftData, and only the relative path is persisted.
struct AttachmentMetadata: Codable, Equatable {
    let filename: String
    let relativePath: String
    let mimeType: String
    let fileSize: Int64
    let sha256: String
}

enum AttachmentStoreError: LocalizedError {
    case invalidRelativePath
    case sourceIsNotAFile
    case sourceIsNotReadable
    case unsupportedImage
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidRelativePath:
            return "The attachment path is invalid."
        case .sourceIsNotAFile:
            return "Please choose a file, not a folder."
        case .sourceIsNotReadable:
            return "The selected file could not be read."
        case .unsupportedImage:
            return "A thumbnail could not be created for this image."
        case .fileTooLarge:
            return "The attachment is too large to import."
        }
    }
}

/// Stores evidence below Application Support/Held/Evidence. Every public path
/// accepted by this type is relative to that directory and is checked for
/// traversal before it is used.
final class AttachmentStore {
    private let fileManager: FileManager
    private let evidenceDirectory: URL

    /// A defensive ceiling for single in-memory restores/imports. Normal file
    /// imports use mapped data for hashing and do not retain the mapped bytes.
    static let maximumAttachmentBytes: Int64 = 512 * 1_024 * 1_024

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) throws {
        self.fileManager = fileManager
        let root: URL
        if let baseDirectory {
            root = baseDirectory
        } else {
            root = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Held", isDirectory: true)
        }
        evidenceDirectory = root.appendingPathComponent("Evidence", isDirectory: true)
        try fileManager.createDirectory(
            at: evidenceDirectory,
            withIntermediateDirectories: true,
            attributes: [FileAttributeKey.protectionKey: FileProtectionType.completeUnlessOpen]
        )
    }

    /// Imports a security-scoped file selected by the user. The source is never
    /// modified and the stored filename is always a new UUID.
    func importFile(from sourceURL: URL) throws -> AttachmentMetadata {
        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let values = try sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isReadableKey, .fileSizeKey]
        )
        guard values.isRegularFile == true else {
            throw AttachmentStoreError.sourceIsNotAFile
        }
        guard values.isReadable != false else {
            throw AttachmentStoreError.sourceIsNotReadable
        }
        if let fileSize = values.fileSize,
           Int64(fileSize) > Self.maximumAttachmentBytes {
            throw AttachmentStoreError.fileTooLarge
        }

        let originalFilename = Self.safeOriginalFilename(sourceURL.lastPathComponent)
        let ext = sourceURL.pathExtension
        let destination = uniqueDestination(pathExtension: ext)

        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } catch {
            throw AttachmentStoreError.sourceIsNotReadable
        }

        do {
            return try metadata(
                for: destination,
                originalFilename: originalFilename,
                explicitMIMEType: nil
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    /// Imports bytes from a validated backup. A new randomized filename is used;
    /// archive-supplied paths are never trusted as destination paths.
    func importData(
        _ data: Data,
        originalFilename: String,
        mimeType explicitMIMEType: String? = nil
    ) throws -> AttachmentMetadata {
        guard Int64(data.count) <= Self.maximumAttachmentBytes else {
            throw AttachmentStoreError.fileTooLarge
        }
        let safeName = Self.safeOriginalFilename(originalFilename)
        let ext = URL(fileURLWithPath: safeName).pathExtension
        let destination = uniqueDestination(pathExtension: ext)
        do {
            try data.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
            return try metadata(
                for: destination,
                originalFilename: safeName,
                explicitMIMEType: explicitMIMEType
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func remove(relativePath: String) throws {
        let fileURL = try url(forRelativePath: relativePath)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    func url(forRelativePath relativePath: String) throws -> URL {
        guard Self.isSafeRelativePath(relativePath) else {
            throw AttachmentStoreError.invalidRelativePath
        }
        let root = evidenceDirectory.standardizedFileURL
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPath), candidate.path != root.path else {
            throw AttachmentStoreError.invalidRelativePath
        }
        return candidate
    }

    /// Returns the total size of regular files currently in the evidence folder.
    func totalBytes() throws -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: evidenceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    /// Creates an in-memory thumbnail without adding another persisted file.
    func thumbnail(
        forRelativePath relativePath: String,
        maxPixelSize: Int = 320
    ) throws -> UIImage {
        guard maxPixelSize > 0 else { throw AttachmentStoreError.unsupportedImage }
        let fileURL = try url(forRelativePath: relativePath)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            throw AttachmentStoreError.unsupportedImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AttachmentStoreError.unsupportedImage
        }
        return UIImage(cgImage: image)
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\0"),
              !path.contains(":") else {
            return false
        }
        // Backslashes are rejected rather than normalized so a backup created on
        // another platform cannot change meaning when restored on iOS.
        guard !path.contains("\\") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".." &&
            component.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F }
        }
    }

    private func uniqueDestination(pathExtension: String) -> URL {
        let safeExtension = pathExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let suffix = safeExtension.isEmpty ? "" : "." + safeExtension
        return evidenceDirectory.appendingPathComponent(UUID().uuidString + suffix)
    }

    private func metadata(
        for fileURL: URL,
        originalFilename: String,
        explicitMIMEType: String?
    ) throws -> AttachmentMetadata {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw AttachmentStoreError.sourceIsNotAFile
        }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let mimeType = Self.mimeType(
            for: fileURL,
            data: data,
            explicitMIMEType: explicitMIMEType
        )
        return AttachmentMetadata(
            filename: originalFilename,
            relativePath: fileURL.lastPathComponent,
            mimeType: mimeType,
            fileSize: Int64(values.fileSize ?? data.count),
            sha256: digest
        )
    }

    private static func mimeType(for fileURL: URL, data: Data, explicitMIMEType: String?) -> String {
        if let explicitMIMEType,
           explicitMIMEType.range(of: #"^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$"#, options: .regularExpression) != nil {
            return explicitMIMEType.lowercased()
        }
        if let type = UTType(filenameExtension: fileURL.pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) {
            return "application/pdf"
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        return "application/octet-stream"
    }

    private static func safeOriginalFilename(_ filename: String) -> String {
        let lastComponent = filename
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init) ?? "Attachment"
        let cleaned = lastComponent.unicodeScalars.map { scalar -> Character in
            if scalar.value < 0x20 || scalar.value == 0x7F || scalar == ":" {
                return "_"
            }
            return Character(scalar)
        }
        let result = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty || result == "." || result == ".." ? "Attachment" : String(result.prefix(180))
    }
}
