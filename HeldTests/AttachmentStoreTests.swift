import XCTest
@testable import Held

final class AttachmentStoreTests: XCTestCase {
    private var temporaryRoot: URL!
    private var store: AttachmentStore!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = try AttachmentStore(baseDirectory: temporaryRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
        store = nil
        temporaryRoot = nil
    }

    func testImportedDataIsHashedAndCanBeRemoved() throws {
        let bytes = Data("receipt".utf8)
        let metadata = try store.importData(
            bytes,
            originalFilename: "receipt.txt",
            mimeType: "text/plain"
        )
        XCTAssertEqual(metadata.fileSize, Int64(bytes.count))
        XCTAssertEqual(metadata.mimeType, "text/plain")
        XCTAssertEqual(metadata.sha256.count, 64)

        let url = try store.url(forRelativePath: metadata.relativePath)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        try store.remove(relativePath: metadata.relativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testFileImportReturnsOnlyAfterFileReachesFinalDestination() throws {
        let source = temporaryRoot.appendingPathComponent("source.txt")
        try Data("original".utf8).write(to: source)
        let metadata = try store.importFile(from: source)
        let destination = try store.url(forRelativePath: metadata.relativePath)
        XCTAssertEqual(try Data(contentsOf: destination), Data("original".utf8))
        XCTAssertNotEqual(destination, source)
    }

    func testTraversalPathsAreRejected() {
        for path in ["../secret", "/absolute", "folder/../../secret", "folder\\secret", ""] {
            XCTAssertFalse(AttachmentStore.isSafeRelativePath(path), path)
            XCTAssertThrowsError(try store.url(forRelativePath: path), path)
        }
    }
}
