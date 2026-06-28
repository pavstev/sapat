import XCTest
@testable import Sapat

/// Covers the import cleanup contract: temp extractions are deleted, the user's own
/// pass-through file is never touched. (The pass-through decision itself is a thin
/// `AVAudioFile(forReading:)` readability check exercised end-to-end in the app.)
final class AudioImporterTests: XCTestCase {

    func testCleanUpLeavesPassThroughOriginals() throws {
        let original = FileManager.default.temporaryDirectory
            .appendingPathComponent("sapat-keep-\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: original.path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(at: original) }

        AudioImporter.cleanUp(.init(url: original, isTemporary: false))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path),
                      "cleanup must never delete the user's own file")
    }

    func testCleanUpRemovesTemporaryExtraction() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sapat-temp-\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: temp.path, contents: Data("x".utf8))

        AudioImporter.cleanUp(.init(url: temp, isTemporary: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
    }
}
