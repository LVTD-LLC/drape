import XCTest
import SwiftData
@testable import Drape

@MainActor final class MigrationTests: XCTestCase {
    func testV2StoreMigratesToV3AndRicherBackupReopensWithEveryPhoto() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("v2.store")
        let photo = DemoData.photo(color: .brown, symbol: "hat.widebrim")
        let studio = DemoData.photo(color: .blue, symbol: "hat.widebrim")
        var details = ItemDetails(); details.name = "My hat"; details.category = .accessories; details.subcategory = "Wide-brim hat"
        let id: UUID
        do {
            let old = try ModelContainer(for: WardrobeSchemaV2.Garment.self, WardrobeSchemaV2.Look.self, configurations: ModelConfiguration(url: url))
            let item = WardrobeSchemaV2.Garment(front: photo, back: photo, label: photo, details: details)
            id = item.id; item.cutout = photo; item.studio = studio; item.useStudio = true; item.isFavorite = true
            try item.setExtraPhotos([photo, studio])
            item.analysisModel = AIModelDefaults.analysis; item.imageModel = AIModelDefaults.image
            old.mainContext.insert(item); old.mainContext.insert(WardrobeSchemaV2.Look(name: "Weekend", garmentIDs: [id]))
            try old.mainContext.save()
        }
        let attributes = ItemAttributes(typeDetail: "Wide-brim", tags: ["summer"],
            originalPrice: OriginalPrice(amount: "89.95", currency: "EUR", source: .user, evidence: ""),
            condition: ConditionAssessment(grade: .veryGood, source: .photo, evidence: "Slight brim creasing"))
        do {
            let migrated = try ModelContainer(for: Garment.self, Look.self, migrationPlan: WardrobeMigrationPlan.self, configurations: ModelConfiguration(url: url))
            let item = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<Garment>()).first)
            XCTAssertEqual(item.id, id); XCTAssertEqual(item.details, details); XCTAssertTrue(item.isFavorite)
            XCTAssertEqual(item.sourcePhotos, [photo, photo, photo, photo, studio])
            XCTAssertEqual(item.cutout, photo); XCTAssertEqual(item.studio, studio); XCTAssertTrue(item.useStudio)
            XCTAssertEqual(item.analysisModel, AIModelDefaults.analysis); XCTAssertEqual(item.imageModel, AIModelDefaults.image)
            XCTAssertEqual(item.attributes, .empty)
            XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<Look>()).first?.garmentIDs, [id])
            try item.setAttributes(attributes); try migrated.mainContext.save()
        }
        let reopened = try ModelContainer(for: Garment.self, Look.self, migrationPlan: WardrobeMigrationPlan.self, configurations: ModelConfiguration(url: url))
        let item = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Garment>()).first)
        XCTAssertEqual(item.attributes, attributes); XCTAssertEqual(item.front, photo); XCTAssertEqual(item.studio, studio)
        let archive = try WardrobeArchive.decode(JSONEncoder().encode(WardrobeArchive.make(context: reopened.mainContext)))
        XCTAssertEqual(archive.version, 3)
        let restoredURL = directory.appendingPathComponent("restored.store")
        do {
            let target = try ModelContainer(for: Garment.self, Look.self, configurations: ModelConfiguration(url: restoredURL))
            XCTAssertEqual(try archive.restore(into: target.mainContext), 1)
        }
        let restoredStore = try ModelContainer(for: Garment.self, Look.self, configurations: ModelConfiguration(url: restoredURL))
        let restored = try XCTUnwrap(restoredStore.mainContext.fetch(FetchDescriptor<Garment>()).first)
        XCTAssertEqual(restored.attributes, attributes); XCTAssertEqual(restored.details, details)
        XCTAssertEqual(restored.sourcePhotos, [photo, photo, photo, photo, studio]); XCTAssertEqual(restored.studio, studio)
        XCTAssertEqual(try restoredStore.mainContext.fetch(FetchDescriptor<Look>()).first?.garmentIDs, [id])
    }

    func testOriginalStoreMigratesWithoutLosingPhotosEditsOrLooks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("wardrobe.store")
        let photos = ["tshirt", "tag", "shoe", "heart", "star"].map { DemoData.photo(color: .brown, symbol: $0) }
        var details = ItemDetails(); details.name = "My edited piece"; details.size = "S"
        let id: UUID
        do {
            // Build the same unversioned schema used by the installed app.
            let old = try ModelContainer(for: WardrobeSchemaV1.Garment.self, WardrobeSchemaV1.Look.self, configurations: ModelConfiguration(url: url))
            let item = WardrobeSchemaV1.Garment(front: photos[0], back: photos[1], label: photos[2], details: details)
            id = item.id; item.cutout = photos[3]; item.studio = photos[4]; item.useStudio = true; item.isFavorite = true
            old.mainContext.insert(item)
            old.mainContext.insert(WardrobeSchemaV1.Look(name: "Sunday", garmentIDs: [id]))
            try old.mainContext.save()
        }
        do {
            let store = try ModelContainer(for: Garment.self, Look.self, migrationPlan: WardrobeMigrationPlan.self, configurations: ModelConfiguration(url: url))
            let item = try XCTUnwrap(store.mainContext.fetch(FetchDescriptor<Garment>()).first)
            XCTAssertEqual(item.id, id); XCTAssertEqual(item.details, details); XCTAssertTrue(item.isFavorite)
            XCTAssertEqual(item.front, photos[0]); XCTAssertEqual(item.back, photos[1]); XCTAssertEqual(item.label, photos[2])
            XCTAssertEqual(item.cutout, photos[3]); XCTAssertEqual(item.studio, photos[4]); XCTAssertTrue(item.useStudio)
            XCTAssertEqual(item.extraPhotos, [])
            XCTAssertEqual(try store.mainContext.fetch(FetchDescriptor<Look>()).first?.garmentIDs, [id])
            try item.setExtraPhotos([photos[0], photos[4]])
            try store.mainContext.save()
        }
        let reopened = try ModelContainer(for: Garment.self, Look.self, migrationPlan: WardrobeMigrationPlan.self, configurations: ModelConfiguration(url: url))
        let item = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Garment>()).first)
        XCTAssertEqual(item.sourcePhotos, Array(photos.prefix(3)) + [photos[0], photos[4]])
        XCTAssertEqual(item.details, details)
    }

    func testBackupExtraPhotosSurviveRestoreAndReopenAndOldBackupsStillRead() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = DemoData.photo(color: .blue, symbol: "shoe")
        let source = try ModelContainer(for: Garment.self, Look.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let item = Garment(front: photo); try item.setExtraPhotos([photo, photo])
        item.analysisModel = AIModelDefaults.analysis
        source.mainContext.insert(item); try source.mainContext.save()
        let archive = try WardrobeArchive.decode(JSONEncoder().encode(WardrobeArchive.make(context: source.mainContext)))
        let url = directory.appendingPathComponent("restored.store")
        do {
            let target = try ModelContainer(for: Garment.self, Look.self, configurations: ModelConfiguration(url: url))
            XCTAssertEqual(try archive.restore(into: target.mainContext), 1)
        }
        let reopened = try ModelContainer(for: Garment.self, Look.self, configurations: ModelConfiguration(url: url))
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Garment>()).first?.sourcePhotos, [photo, photo, photo])
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Garment>()).first?.analysisModel, AIModelDefaults.analysis)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
        json["version"] = 1
        var records = try XCTUnwrap(json["items"] as? [[String: Any]])
        records[0].removeValue(forKey: "extraPhotos"); records[0].removeValue(forKey: "attributes"); json["items"] = records
        let legacy = try WardrobeArchive.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.items.first?.front, photo); XCTAssertNil(legacy.items.first?.extraPhotos)
        XCTAssertNil(legacy.items.first?.attributes)
        json["version"] = 2
        XCTAssertNil(try WardrobeArchive.decode(JSONSerialization.data(withJSONObject: json)).items.first?.attributes)
    }
}
