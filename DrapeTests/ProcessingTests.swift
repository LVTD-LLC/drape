import XCTest
import SwiftData
@testable import Drape

private actor TestWardrobeAI: WardrobeAI {
    var analysisCalls = 0
    var studioCalls = 0
    var receivedPhotos: [Data] = []
    var failStudio = false
    let photo: Data
    init(photo: Data, failStudio: Bool = false) { self.photo = photo; self.failStudio = failStudio }
    func allowStudio() { failStudio = false }
    func counts() -> [Int] { [analysisCalls, studioCalls] }
    func analyze(photos: [PhotoInput], configuration: AIConfiguration) async throws -> ItemDetails {
        analysisCalls += 1; receivedPhotos = photos.map(\.data)
        var details = ItemDetails(); details.name = "AI shirt"; details.category = .tops; details.color = "Blue"
        return details
    }
    func studioPhoto(front: Data, configuration: AIConfiguration) async throws -> Data {
        studioCalls += 1
        if failStudio { throw AIError.http(502) }
        return photo
    }
}

@MainActor final class ProcessingTests: XCTestCase {
    private var stores: [ModelContainer] = []
    private func context() throws -> ModelContext {
        let store = try ModelContainer(for: Garment.self, Look.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        stores.append(store); return store.mainContext
    }
    private func wait(_ processor: ProcessingCoordinator) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !processor.activeIDs.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(processor.activeIDs.isEmpty)
    }
    func testAutomaticFlowAppliesDetailsAndStudioOnceAndKeepsEditsAndSources() async throws {
        let context = try context()
        let original = DemoData.photo(color: .blue, symbol: "tshirt")
        let studio = DemoData.photo(color: .red, symbol: "tshirt")
        let service = TestWardrobeAI(photo: studio)
        let processor = ProcessingCoordinator(service: service, prepare: { _, _ in LocalPhotoResult(cutout: nil, labelText: "") })
        let item = Garment(front: original)
        try item.setExtraPhotos(Array(repeating: original, count: 5))
        context.insert(item); try context.save()
        processor.start(item, context: context, configuration: .automatic)
        processor.start(item, context: context, configuration: .automatic)
        item.details.name = "My own name"
        try context.save()
        try await wait(processor)
        XCTAssertEqual(item.details.name, "My own name")
        XCTAssertEqual(item.details.category, .tops)
        XCTAssertEqual(item.details.color, "Blue")
        XCTAssertNil(item.suggestions)
        XCTAssertEqual(item.displayPhoto, studio)
        XCTAssertEqual(item.sourcePhotos, Array(repeating: original, count: 6))
        XCTAssertEqual(item.processingState, "ready")
        processor.start(item, context: context, configuration: .automatic)
        try await wait(processor)
        let counts = await service.counts(), received = await service.receivedPhotos
        XCTAssertEqual(counts, [1, 1]); XCTAssertEqual(received.count, 6)
    }
    func testStudioFailureKeepsAnalysisAndExplicitRetrySkipsIt() async throws {
        let context = try context(), photo = DemoData.photo(color: .brown, symbol: "tshirt")
        let service = TestWardrobeAI(photo: photo, failStudio: true)
        let processor = ProcessingCoordinator(service: service, prepare: { _, _ in LocalPhotoResult(cutout: nil, labelText: "") })
        let item = Garment(front: photo); context.insert(item); try context.save()
        processor.start(item, context: context, configuration: .automatic)
        try await wait(processor)
        XCTAssertEqual(item.details.name, "AI shirt"); XCTAssertNil(item.studio)
        XCTAssertEqual(item.processingState, "attention")
        var counts = await service.counts(); XCTAssertEqual(counts, [1, 1])
        item.details.name = "Edited name"
        await service.allowStudio()
        processor.start(item, context: context, configuration: .automatic)
        try await wait(processor)
        counts = await service.counts(); XCTAssertEqual(counts, [1, 2])
        XCTAssertEqual(item.details.name, "Edited name"); XCTAssertEqual(item.displayPhoto, photo)
    }
    func testPhotosOnlyDoesNotContactAI() async throws {
        let context = try context(), photo = DemoData.photo(color: .brown, symbol: "tshirt")
        let service = TestWardrobeAI(photo: photo)
        let processor = ProcessingCoordinator(service: service, prepare: { _, _ in LocalPhotoResult(cutout: nil, labelText: "") })
        let item = Garment(front: photo); context.insert(item); try context.save()
        processor.start(item, context: context)
        try await wait(processor)
        let counts = await service.counts(); XCTAssertEqual(counts, [0, 0])
        XCTAssertEqual(item.processingState, "ready"); XCTAssertEqual(item.front, photo)
    }
}
