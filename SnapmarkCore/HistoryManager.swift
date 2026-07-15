import AppKit
import Foundation

public struct HistoryEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
}

@MainActor
public final class HistoryManager {
    public static let maxEntries = 5

    public private(set) var entries: [HistoryEntry] = []

    private let fileManager: FileManager
    private let manifestURL: URL
    private let imagesDirectory: URL

    public init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = appSupport
            .appendingPathComponent("com.rbm.snapmark")
            .appendingPathComponent("History")
        imagesDirectory = base
        manifestURL = base.appendingPathComponent("manifest.json")
        fileManager = fm
        loadManifest()
    }

    // MARK: - Public API

    public func addEntry(pngData: Data) throws {
        let id = UUID()
        let date = Date()

        try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        let imageURL = imagesDirectory.appendingPathComponent("\(id.uuidString).png")
        let thumbURL = imagesDirectory.appendingPathComponent("\(id.uuidString)_thumb.png")
        try pngData.write(to: imageURL)

        let thumbnailData = try generateThumbnail(from: pngData)
        try thumbnailData.write(to: thumbURL)

        entries.insert(HistoryEntry(id: id, date: date), at: 0)

        if entries.count > Self.maxEntries {
            let removed = entries.removeLast()
            removeFiles(for: removed.id)
        }

        saveManifest()
    }

    public func fullImageData(for id: UUID) -> Data? {
        let url = imagesDirectory.appendingPathComponent("\(id.uuidString).png")
        return try? Data(contentsOf: url)
    }

    public func thumbnailData(for id: UUID) -> Data? {
        let url = imagesDirectory.appendingPathComponent("\(id.uuidString)_thumb.png")
        return try? Data(contentsOf: url)
    }

    public func clearAll() {
        entries.removeAll()
        try? fileManager.removeItem(at: imagesDirectory)
        saveManifest()
    }

    // MARK: - Persistence

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              var decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else {
            entries = []
            return
        }
        decoded.removeAll { entry in
            let url = imagesDirectory.appendingPathComponent("\(entry.id.uuidString).png")
            return !fileManager.fileExists(atPath: url.path)
        }
        entries = decoded
        cleanupOrphans()
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? data.write(to: manifestURL)
    }

    private func removeFiles(for id: UUID) {
        let imageURL = imagesDirectory.appendingPathComponent("\(id.uuidString).png")
        let thumbURL = imagesDirectory.appendingPathComponent("\(id.uuidString)_thumb.png")
        try? fileManager.removeItem(at: imageURL)
        try? fileManager.removeItem(at: thumbURL)
    }

    private func cleanupOrphans() {
        let validIDs = Set(entries.map { $0.id.uuidString })
        guard let files = try? fileManager.contentsOfDirectory(atPath: imagesDirectory.path)
        else { return }
        for file in files {
            if file == "manifest.json" { continue }
            let id = file
                .replacingOccurrences(of: "_thumb.png", with: "")
                .replacingOccurrences(of: ".png", with: "")
            if !validIDs.contains(id) {
                try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(file))
            }
        }
    }

    private func generateThumbnail(from pngData: Data) throws -> Data {
        guard let image = NSImage(data: pngData) else {
            throw HistoryError.thumbnailGenerationFailed
        }
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            throw HistoryError.thumbnailGenerationFailed
        }
        let scale = min(40 / max(size.width, 1), 25 / max(size.height, 1), 1)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1)
        resized.unlockFocus()

        guard let cgImage = resized.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw HistoryError.thumbnailGenerationFailed
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:])
        else {
            throw HistoryError.thumbnailGenerationFailed
        }
        return data
    }
}

public enum HistoryError: Error {
    case thumbnailGenerationFailed
}
