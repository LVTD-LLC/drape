import XCTest
import SwiftData
import UIKit
@testable import Drape

@MainActor final class WardrobeTests: XCTestCase {
    private var retainedContainers: [ModelContainer] = []
    private func container() throws -> ModelContainer {
        let container = try ModelContainer(for: Garment.self, Look.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        retainedContainers.append(container)
        return container
    }

    func testBackupRoundTripRetainsPhotosDetailsAndLookMembership() throws {
        let source = try container().mainContext
        var details = ItemDetails()
        details.name = "Cream cardigan"; details.category = .tops; details.size = "M"; details.care = "Hand wash"
        let image = DemoData.photo(color: .brown, symbol: "tshirt.fill")
        let item = Garment(front: image, back: image, label: image, details: details)
        item.isFavorite = true
        source.insert(item)
        source.insert(Look(name: "Sunday", notes: "Coffee with friends", garmentIDs: [item.id]))
        try source.save()
        let archive = try WardrobeArchive.decode(JSONEncoder().encode(WardrobeArchive.make(context: source)))
        XCTAssertEqual(archive.items.first?.front, image)
        let target = try container().mainContext
        XCTAssertEqual(try archive.restore(into: target), 1)
        let restored = try XCTUnwrap(target.fetch(FetchDescriptor<Garment>()).first)
        XCTAssertEqual(restored.id, item.id)
        XCTAssertEqual(restored.details, details)
        XCTAssertTrue(restored.isFavorite)
        XCTAssertEqual(restored.front, image)
        XCTAssertEqual(restored.back, image)
        XCTAssertEqual(restored.label, image)
        XCTAssertNotNil(UIImage(data: restored.front))
        XCTAssertNotNil(restored.back)
        XCTAssertNotNil(restored.label)
        XCTAssertEqual(try target.fetch(FetchDescriptor<Look>()).first?.garmentIDs, [item.id])
        restored.details.name = "My corrected name"
        try target.save()
        XCTAssertEqual(try archive.restore(into: target), 0)
        XCTAssertEqual(restored.details.name, "My corrected name")
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<Look>()), 1)
    }

    func testBackupRejectsUnknownVersionCorruptImageAndDuplicateIDs() throws {
        var archive = WardrobeArchive(items: [], looks: [])
        archive.version = 99
        XCTAssertThrowsError(try WardrobeArchive.decode(JSONEncoder().encode(archive)))
        let item = WardrobeArchive.ArchivedItem(id: UUID(), createdAt: .now, details: .empty, isFavorite: false,
                                              front: Data("bad photo".utf8), back: nil, label: nil, cutout: nil, studio: nil, useStudio: false)
        archive = WardrobeArchive(items: [item], looks: [])
        XCTAssertThrowsError(try WardrobeArchive.decode(JSONEncoder().encode(archive)))
        archive.items.append(item)
        XCTAssertThrowsError(try WardrobeArchive.decode(JSONEncoder().encode(archive)))
    }

    func testInterruptedProcessingPreservesOriginalAndEdits() throws {
        let context = try container().mainContext
        let data = DemoData.photo(color: .brown, symbol: "tshirt.fill")
        var details = ItemDetails(); details.name = "My shirt"
        let item = Garment(front: data, details: details)
        item.processingState = "processing"
        context.insert(item); try context.save()
        try ProcessingCoordinator().recoverInterrupted(in: context)
        XCTAssertEqual(item.processingState, "attention")
        XCTAssertEqual(item.front, data)
        XCTAssertEqual(item.details.name, "My shirt")
    }

    func testImageNormalizationBoundsDimensionsAndRejectsNonImages() throws {
        let original = DemoData.photo(color: .blue, symbol: "tshirt.fill")
        let normalized = try ImageTools.normalized(original, maxDimension: 300)
        let image = try XCTUnwrap(UIImage(data: normalized))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 300)
        XCTAssertThrowsError(try ImageTools.normalized(Data("not an image".utf8)))
    }

    func testStudioPhotoDoesNotReplaceOriginalUntilChosen() {
        let item = Garment(front: Data([1]))
        item.cutout = Data([2]); item.studio = Data([3])
        XCTAssertEqual(item.displayPhoto, Data([2]))
        item.useStudio = true
        XCTAssertEqual(item.displayPhoto, Data([3]))
        XCTAssertEqual(item.front, Data([1]))
    }

    func testPersistenceAcrossContainerReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("wardrobe.store")
        let id: UUID
        do {
            let store = try ModelContainer(for: Garment.self, Look.self, configurations: ModelConfiguration(url: url))
            var details = ItemDetails(); details.name = "Saved after relaunch"
            let item = Garment(front: DemoData.photo(color: .red, symbol: "tshirt"), details: details)
            id = item.id
            store.mainContext.insert(item); try store.mainContext.save()
        }
        let reopened = try ModelContainer(for: Garment.self, Look.self, configurations: ModelConfiguration(url: url))
        let item = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Garment>()).first)
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.details.name, "Saved after relaunch")
        XCTAssertNotNil(UIImage(data: item.front))
    }
}
