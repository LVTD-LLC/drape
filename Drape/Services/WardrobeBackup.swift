import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct WardrobeArchive: Codable, Sendable {
    var version = 1
    var exportedAt = Date()
    var items: [ArchivedItem]
    var looks: [ArchivedLook]

    struct ArchivedItem: Codable, Sendable {
        let id: UUID
        let createdAt: Date
        let details: ItemDetails
        let isFavorite: Bool
        let front: Data
        let back: Data?
        let label: Data?
        let cutout: Data?
        let studio: Data?
        let useStudio: Bool
    }
    struct ArchivedLook: Codable, Sendable {
        let id: UUID
        let name: String
        let notes: String
        let createdAt: Date
        let garmentIDs: [UUID]
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 100_000_000 else { throw BackupError.tooLarge }
        let archive = try JSONDecoder().decode(Self.self, from: data)
        guard archive.version == 1 else { throw BackupError.unsupportedVersion }
        guard archive.items.count <= 2000, archive.looks.count <= 2000 else { throw BackupError.tooLarge }
        guard Set(archive.items.map(\.id)).count == archive.items.count,
              Set(archive.looks.map(\.id)).count == archive.looks.count else { throw BackupError.invalid }
        for item in archive.items {
            for data in [item.front, item.back, item.label, item.cutout, item.studio].compactMap({ $0 }) {
                guard data.count < 10_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
                      CGImageSourceGetCount(source) > 0,
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      width > 0, height > 0, width <= 10000, height <= 10000 else { throw BackupError.invalid }
            }
        }
        return archive
    }

    @MainActor static func make(context: ModelContext) throws -> Self {
        let items = try context.fetch(FetchDescriptor<Garment>()).map {
            ArchivedItem(id: $0.id, createdAt: $0.createdAt, details: $0.details, isFavorite: $0.isFavorite,
                         front: $0.front, back: $0.back, label: $0.label, cutout: $0.cutout, studio: $0.studio, useStudio: $0.useStudio)
        }
        let looks = try context.fetch(FetchDescriptor<Look>()).map {
            ArchivedLook(id: $0.id, name: $0.name, notes: $0.notes, createdAt: $0.createdAt, garmentIDs: $0.garmentIDs)
        }
        return Self(items: items, looks: looks)
    }

    @MainActor func restore(into context: ModelContext) throws -> Int {
        let existing = Set(try context.fetch(FetchDescriptor<Garment>()).map(\.id))
        let existingLooks = Set(try context.fetch(FetchDescriptor<Look>()).map(\.id))
        let knownIDs = existing.union(items.map(\.id))
        var added = 0
        do {
            for record in items where !existing.contains(record.id) {
                let item = Garment(front: record.front, back: record.back, label: record.label, details: record.details)
                item.id = record.id; item.createdAt = record.createdAt; item.isFavorite = record.isFavorite
                item.cutout = record.cutout
                item.studio = record.studio
                item.useStudio = record.useStudio && item.studio != nil
                item.thumbnail = ImageTools.thumbnail(item.displayPhoto)
                context.insert(item); added += 1
            }
            for record in looks where !existingLooks.contains(record.id) {
                let look = Look(name: record.name, notes: record.notes, garmentIDs: Array(Set(record.garmentIDs).intersection(knownIDs)))
                look.id = record.id; look.createdAt = record.createdAt; context.insert(look)
            }
            try context.save()
            return added
        } catch { context.rollback(); throw error }
    }
}

struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.invalid }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

enum BackupError: LocalizedError {
    case invalid, tooLarge, unsupportedVersion
    var errorDescription: String? {
        switch self {
        case .invalid: "This isn’t a valid Drape wardrobe backup. Nothing has been changed."
        case .tooLarge: "This backup exceeds the first version’s 100 MB or 2,000-item limit. Nothing has been changed."
        case .unsupportedVersion: "This backup was made with a different version of Drape. Update the app and try again."
        }
    }
}
