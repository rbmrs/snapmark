import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import SnapmarkCore

/// These tests point `HistoryManager` at a throwaway temp directory via the injected
/// `baseURL`, so they never touch the real Application Support history.
///
/// `HistoryManager` is `@MainActor`, so every test that talks to it is annotated
/// `@MainActor`. `setUpWithError`/`tearDownWithError` stay non-isolated and only do
/// plain file-system work, to avoid an isolation mismatch with XCTestCase's overrides.
final class HistoryManagerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapmarkHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - Manifest loading

    @MainActor
    func testMissingManifestYieldsEmptyHistoryAndSkipsCleanup() throws {
        let stray = UUID().uuidString
        try writeStubFile(named: "\(stray).png")

        let manager = HistoryManager(baseURL: tempDirectory)

        XCTAssertTrue(manager.entries.isEmpty)
        // `loadManifest` returns before `cleanupOrphans` when the manifest cannot be read,
        // so images stay on disk forever once the manifest disappears.
        XCTAssertTrue(exists("\(stray).png"))
    }

    @MainActor
    func testCorruptManifestYieldsEmptyHistoryWithoutDeletingImages() throws {
        let stray = UUID().uuidString
        try writeStubFile(named: "\(stray).png")
        try Data("{ this is not json".utf8)
            .write(to: historyDirectory.appendingPathComponent("manifest.json"))

        let manager = HistoryManager(baseURL: tempDirectory)

        XCTAssertTrue(manager.entries.isEmpty)
        // Same early return as above: a corrupt manifest strands every image on disk.
        XCTAssertTrue(exists("\(stray).png"))
        XCTAssertTrue(exists("manifest.json"))
    }

    @MainActor
    func testEntriesWhoseImageIsMissingAreDropped() throws {
        let present = UUID()
        let missing = UUID()
        try writeManifest([entry(present), entry(missing)])
        try writeStubFile(named: "\(present.uuidString).png")

        let manager = HistoryManager(baseURL: tempDirectory)

        XCTAssertEqual(manager.entries.map(\.id), [present])
    }

    // MARK: - Orphan reconciliation

    @MainActor
    func testOrphanImagesAndThumbnailsAreRemovedWhileValidOnesSurvive() throws {
        let kept = UUID()
        let orphan = UUID()
        try writeManifest([entry(kept)])
        try writeStubFile(named: "\(kept.uuidString).png")
        try writeStubFile(named: "\(kept.uuidString)_thumb.png")
        try writeStubFile(named: "\(orphan.uuidString).png")
        try writeStubFile(named: "\(orphan.uuidString)_thumb.png")

        let manager = HistoryManager(baseURL: tempDirectory)

        XCTAssertEqual(manager.entries.map(\.id), [kept])
        XCTAssertTrue(exists("\(kept.uuidString).png"))
        XCTAssertTrue(exists("\(kept.uuidString)_thumb.png"))
        XCTAssertFalse(exists("\(orphan.uuidString).png"))
        XCTAssertFalse(exists("\(orphan.uuidString)_thumb.png"))
        XCTAssertTrue(exists("manifest.json"))
    }

    @MainActor
    func testThumbnailOfDroppedEntryIsAlsoRemoved() throws {
        let kept = UUID()
        let halfDeleted = UUID()
        try writeManifest([entry(kept), entry(halfDeleted)])
        try writeStubFile(named: "\(kept.uuidString).png")
        try writeStubFile(named: "\(kept.uuidString)_thumb.png")
        // Full image is gone but the thumbnail survived: the entry is dropped from the
        // manifest, and the stale thumbnail must be swept up by `cleanupOrphans`.
        try writeStubFile(named: "\(halfDeleted.uuidString)_thumb.png")

        let manager = HistoryManager(baseURL: tempDirectory)

        XCTAssertEqual(manager.entries.map(\.id), [kept])
        XCTAssertFalse(exists("\(halfDeleted.uuidString)_thumb.png"))
        XCTAssertTrue(exists("\(kept.uuidString)_thumb.png"))
    }

    @MainActor
    func testCleanupDeletesEveryUnrecognisedFileInTheHistoryDirectory() throws {
        let kept = UUID()
        try writeManifest([entry(kept)])
        try writeStubFile(named: "\(kept.uuidString).png")
        try writeStubFile(named: "notes.txt")
        try writeStubFile(named: "manifest.json.tmp")

        let manager = HistoryManager(baseURL: tempDirectory)

        XCTAssertEqual(manager.entries.map(\.id), [kept])
        // Characterisation test, not an endorsement: `cleanupOrphans` only exempts the
        // exact name "manifest.json", strips "_thumb.png"/".png" anywhere in the name,
        // and deletes anything left over. Any unrelated file that lands in this directory
        // (a Finder .DS_Store, a partially written "manifest.json.tmp", a user's own file)
        // is destroyed on the next launch. Worth tightening to a UUID-shaped name check.
        XCTAssertFalse(exists("notes.txt"))
        XCTAssertFalse(exists("manifest.json.tmp"))
        XCTAssertTrue(exists("manifest.json"))
    }

    // MARK: - Retention

    @MainActor
    func testRetentionLimitEvictsOldestEntryAndItsFiles() throws {
        let seeded = (0..<HistoryManager.maxEntries).map { _ in UUID() }
        try writeManifest(seeded.map { entry($0) })
        for id in seeded {
            try writeStubFile(named: "\(id.uuidString).png")
            try writeStubFile(named: "\(id.uuidString)_thumb.png")
        }

        let manager = HistoryManager(baseURL: tempDirectory)
        XCTAssertEqual(manager.entries.count, HistoryManager.maxEntries)

        // Depends on AppKit: `addEntry` builds a thumbnail through NSImage, so this needs
        // real PNG bytes and a working graphics context.
        try manager.addEntry(pngData: makePNGData())

        XCTAssertEqual(manager.entries.count, HistoryManager.maxEntries)
        let evicted = try XCTUnwrap(seeded.last)
        XCTAssertFalse(manager.entries.contains { $0.id == evicted })
        XCTAssertFalse(exists("\(evicted.uuidString).png"))
        XCTAssertFalse(exists("\(evicted.uuidString)_thumb.png"))
        // Newest first, older entries keep their relative order.
        XCTAssertEqual(manager.entries.dropFirst().map(\.id), Array(seeded.dropLast()))
    }

    // MARK: - Save / load round-trip

    @MainActor
    func testAddEntryRoundTripsThroughAFreshManager() throws {
        let manager = HistoryManager(baseURL: tempDirectory)
        // Depends on AppKit (see above).
        let png = try makePNGData(width: 12, height: 9)
        try manager.addEntry(pngData: png)

        let saved = try XCTUnwrap(manager.entries.first)

        let reloaded = HistoryManager(baseURL: tempDirectory)
        XCTAssertEqual(reloaded.entries.map(\.id), [saved.id])
        let reloadedEntry = try XCTUnwrap(reloaded.entries.first)
        XCTAssertEqual(
            reloadedEntry.date.timeIntervalSinceReferenceDate,
            saved.date.timeIntervalSinceReferenceDate,
            accuracy: 0.001
        )
        XCTAssertEqual(reloaded.fullImageData(for: saved.id), png)
        XCTAssertNotNil(reloaded.thumbnailData(for: saved.id))
        XCTAssertNil(reloaded.fullImageData(for: UUID()))
        XCTAssertNil(reloaded.thumbnailData(for: UUID()))
    }

    @MainActor
    func testClearAllRemovesEntriesAndFilesButKeepsAReadableManifest() throws {
        let manager = HistoryManager(baseURL: tempDirectory)
        // Depends on AppKit (see above).
        let png = try makePNGData()
        try manager.addEntry(pngData: png)
        let id = try XCTUnwrap(manager.entries.first?.id)

        manager.clearAll()

        XCTAssertTrue(manager.entries.isEmpty)
        XCTAssertNil(manager.fullImageData(for: id))
        XCTAssertFalse(exists("\(id.uuidString).png"))
        XCTAssertFalse(exists("\(id.uuidString)_thumb.png"))
        XCTAssertTrue(exists("manifest.json"))

        let reloaded = HistoryManager(baseURL: tempDirectory)
        XCTAssertTrue(reloaded.entries.isEmpty)
    }

    // MARK: - Failure handling

    @MainActor
    func testAddEntryWithNonImageDataThrowsAndRecordsNoEntry() throws {
        let manager = HistoryManager(baseURL: tempDirectory)

        XCTAssertThrowsError(try manager.addEntry(pngData: Data("definitely not a png".utf8))) { error in
            XCTAssertTrue(error is HistoryError, "expected HistoryError, got \(error)")
        }

        XCTAssertTrue(manager.entries.isEmpty)

        // `addEntry` generates the thumbnail before writing anything, so a thumbnail
        // failure leaves no untracked .png behind. The history directory itself may not
        // even exist yet, hence the tolerant read.
        let leftovers = ((try? FileManager.default
            .contentsOfDirectory(atPath: historyDirectory.path)) ?? [])
            .filter { $0.hasSuffix(".png") }
        XCTAssertTrue(leftovers.isEmpty, "expected no orphan images, found \(leftovers)")
    }

    // MARK: - Helpers

    private var historyDirectory: URL {
        tempDirectory
            .appendingPathComponent("com.rbm.snapmark", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }

    private func entry(_ id: UUID, date: Date = Date()) -> HistoryEntry {
        HistoryEntry(id: id, date: date)
    }

    private func writeManifest(_ entries: [HistoryEntry]) throws {
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: historyDirectory.appendingPathComponent("manifest.json"))
    }

    private func writeStubFile(named name: String) throws {
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        try Data("stub".utf8).write(to: historyDirectory.appendingPathComponent(name))
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: historyDirectory.appendingPathComponent(name).path)
    }

    private func makePNGData(width: Int = 8, height: Int = 6) throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = try XCTUnwrap(context.makeImage())
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }
}
