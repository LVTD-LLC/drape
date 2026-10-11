import Foundation
import SwiftData

enum Category: String, Codable, CaseIterable, Identifiable, Sendable {
    case tops = "Tops", bottoms = "Bottoms", dresses = "Dresses", outerwear = "Outerwear"
    case shoes = "Shoes", bags = "Bags", accessories = "Accessories", other = "Other"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .tops: "tshirt"
        case .bottoms: "figure.walk"
        case .dresses: "figure.dress.line.vertical.figure"
        case .outerwear: "jacket"
        case .shoes: "shoe"
        case .bags: "handbag"
        case .accessories: "sunglasses"
        case .other: "square.grid.2x2"
        }
    }
}

enum PhotoRole: String, CaseIterable, Identifiable, Sendable {
    case front = "Front", back = "Back", label = "Label"
    var id: String { rawValue }
}

struct ItemDetails: Codable, Equatable, Sendable {
    var name = ""
    var category: Category = .other
    var subcategory = ""
    var color = ""
    var brand = ""
    var size = ""
    var material = ""
    var pattern = ""
    var season = ""
    var care = ""
    var notes = ""

    static let empty = ItemDetails()
    var searchableText: String {
        [name, category.rawValue, subcategory, color, brand, size, material, pattern, season, notes].joined(separator: " ")
    }
}

enum WardrobeSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Garment.self, Look.self] }
    @Model final class Garment {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var details: ItemDetails
        var isFavorite: Bool
        @Attribute(.externalStorage) var front: Data
        @Attribute(.externalStorage) var back: Data?
        @Attribute(.externalStorage) var label: Data?
        @Attribute(.externalStorage) var cutout: Data?
        @Attribute(.externalStorage) var studio: Data?
        var thumbnail: Data?
        var useStudio: Bool
        var suggestions: ItemDetails?
        var labelText: String
        var processingState: String
        var processingMessage: String
        var analysisModel: String?
        var imageModel: String?

        init(front: Data, back: Data? = nil, label: Data? = nil, details: ItemDetails = .empty) {
            id = UUID(); createdAt = .now; self.front = front; self.back = back; self.label = label
            self.details = details; isFavorite = false; useStudio = false; labelText = ""
            processingState = "idle"; processingMessage = ""
        }
        var displayName: String { details.name.isEmpty ? "New piece" : details.name }
        var displayPhoto: Data { (useStudio ? studio : nil) ?? cutout ?? front }
    }

    @Model final class Look {
        @Attribute(.unique) var id: UUID
        var name: String
        var notes: String
        var createdAt: Date
        var garmentIDs: [UUID]
        init(name: String, notes: String = "", garmentIDs: [UUID]) {
            self.id = UUID(); self.name = name; self.notes = notes; self.createdAt = .now; self.garmentIDs = garmentIDs
        }
    }
}

enum WardrobeSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Garment.self, Look.self] }
    @Model final class Garment {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var details: ItemDetails
        var isFavorite: Bool
        @Attribute(.externalStorage) var front: Data
        @Attribute(.externalStorage) var back: Data?
        @Attribute(.externalStorage) var label: Data?
        @Attribute(.externalStorage) var cutout: Data?
        @Attribute(.externalStorage) var studio: Data?
        @Attribute(.externalStorage) var extraPhotoData: Data?
        var thumbnail: Data?
        var useStudio: Bool
        var suggestions: ItemDetails?
        var labelText: String
        var processingState: String
        var processingMessage: String
        var analysisModel: String?
        var imageModel: String?

        init(front: Data, back: Data? = nil, label: Data? = nil, details: ItemDetails = .empty) {
            id = UUID(); createdAt = .now; self.front = front; self.back = back; self.label = label
            self.details = details; isFavorite = false; useStudio = false; labelText = ""
            processingState = "idle"; processingMessage = ""
        }
        var extraPhotos: [Data] {
            get { extraPhotoData.flatMap { try? JSONDecoder().decode([Data].self, from: $0) } ?? [] }
        }
        func setExtraPhotos(_ photos: [Data]) throws {
            extraPhotoData = photos.isEmpty ? nil : try JSONEncoder().encode(photos)
        }
        var sourcePhotos: [Data] { [front] + [back, label].compactMap { $0 } + extraPhotos }
        var needsAI: Bool { analysisModel == nil || studio == nil }
        var displayName: String { details.name.isEmpty ? "New piece" : details.name }
        var displayPhoto: Data { (useStudio ? studio : nil) ?? cutout ?? front }
    }

    @Model final class Look {
        @Attribute(.unique) var id: UUID
        var name: String
        var notes: String
        var createdAt: Date
        var garmentIDs: [UUID]
        init(name: String, notes: String = "", garmentIDs: [UUID]) {
            self.id = UUID(); self.name = name; self.notes = notes; self.createdAt = .now; self.garmentIDs = garmentIDs
        }
    }
}

enum WardrobeSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [Garment.self, Look.self] }
    @Model final class Garment {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var details: ItemDetails
        var isFavorite: Bool
        @Attribute(.externalStorage) var front: Data
        @Attribute(.externalStorage) var back: Data?
        @Attribute(.externalStorage) var label: Data?
        @Attribute(.externalStorage) var cutout: Data?
        @Attribute(.externalStorage) var studio: Data?
        @Attribute(.externalStorage) var extraPhotoData: Data?
        var thumbnail: Data?
        var useStudio: Bool
        var suggestions: ItemDetails?
        var labelText: String
        var processingState: String
        var processingMessage: String
        var analysisModel: String?
        var imageModel: String?
        var attributesData: Data?

        init(front: Data, back: Data? = nil, label: Data? = nil, details: ItemDetails = .empty) {
            id = UUID(); createdAt = .now; self.front = front; self.back = back; self.label = label
            self.details = details; isFavorite = false; useStudio = false; labelText = ""
            processingState = "idle"; processingMessage = ""
        }
        var extraPhotos: [Data] {
            get { extraPhotoData.flatMap { try? JSONDecoder().decode([Data].self, from: $0) } ?? [] }
        }
        func setExtraPhotos(_ photos: [Data]) throws {
            extraPhotoData = photos.isEmpty ? nil : try JSONEncoder().encode(photos)
        }
        var sourcePhotos: [Data] { [front] + [back, label].compactMap { $0 } + extraPhotos }
        var attributes: ItemAttributes {
            attributesData.flatMap { try? JSONDecoder().decode(ItemAttributes.self, from: $0) } ?? .empty
        }
        func setAttributes(_ value: ItemAttributes) throws {
            attributesData = try JSONEncoder().encode(value.validated())
        }
        var needsAI: Bool { analysisModel == nil || studio == nil }
        var displayName: String { details.name.isEmpty ? "New piece" : details.name }
        var displayPhoto: Data { (useStudio ? studio : nil) ?? cutout ?? front }
    }

    @Model final class Look {
        @Attribute(.unique) var id: UUID
        var name: String
        var notes: String
        var createdAt: Date
        var garmentIDs: [UUID]
        init(name: String, notes: String = "", garmentIDs: [UUID]) {
            self.id = UUID(); self.name = name; self.notes = notes; self.createdAt = .now; self.garmentIDs = garmentIDs
        }
    }
}

typealias Garment = WardrobeSchemaV3.Garment
typealias Look = WardrobeSchemaV3.Look

enum WardrobeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [WardrobeSchemaV1.self, WardrobeSchemaV2.self, WardrobeSchemaV3.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: WardrobeSchemaV1.self, toVersion: WardrobeSchemaV2.self),
         .lightweight(fromVersion: WardrobeSchemaV2.self, toVersion: WardrobeSchemaV3.self)]
    }
}
