import XCTest
import SwiftData
@testable import Drape

@MainActor final class ItemAttributesTests: XCTestCase {
    func testAccessoryTypesAreGranularAndLegacyDescriptionsStillBrowse() {
        for (raw, expected) in [("Wide-brim hat", "Hats"), ("ring", "Rings"), ("Pendant necklace", "Necklaces"), ("watch", "Watches")] {
            var details = ItemDetails(); details.category = .accessories; details.subcategory = raw
            XCTAssertEqual(ItemTaxonomy.type(for: details), expected)
            XCTAssertEqual(details.subcategory, raw)
        }
    }

    func testTagsAreNormalizedAndCombinedFiltersUseAllSelectedTags() throws {
        var details = ItemDetails(); details.category = .accessories; details.subcategory = "Hats"
        let attributes = try ItemAttributes(tags: [" Summer ", "CASUAL", "summer", "", "wide   brim"],
            condition: ConditionAssessment(grade: .veryGood, source: .photo, evidence: "Minor creasing visible")).validated()
        XCTAssertEqual(attributes.tags, ["casual", "summer", "wide brim"])
        var filter = WardrobeFilter(category: .accessories, type: "Hats", tags: ["summer", "casual"], condition: .veryGood)
        XCTAssertTrue(filter.matches(details: details, attributes: attributes, favorite: false, search: "wide brim"))
        filter.tags.insert("formal")
        XCTAssertFalse(filter.matches(details: details, attributes: attributes, favorite: false, search: ""))
        filter.tags = []; filter.type = "Rings"
        XCTAssertFalse(filter.matches(details: details, attributes: attributes, favorite: false, search: ""))
    }

    func testPriceRequiresAnUnambiguousCurrencyAndPhotoEvidence() throws {
        let known = OriginalPrice(amount: "89.95", currency: "EUR", source: .photo, evidence: "EUR 89.95")
        XCTAssertNoThrow(try known.validate())
        for bad in [
            OriginalPrice(amount: "89.95", currency: "$", source: .photo, evidence: "$89.95"),
            OriginalPrice(amount: "89.95", currency: "EUR", source: .photo, evidence: ""),
            OriginalPrice(amount: "-2", currency: "EUR", source: .user, evidence: ""),
            OriginalPrice(amount: "1,000", currency: "EUR", source: .user, evidence: ""),
            OriginalPrice(amount: "NaN", currency: "EUR", source: .user, evidence: "")
        ] { XCTAssertThrowsError(try bad.validate()) }
        XCTAssertNil(ItemAttributes.empty.originalPrice)
        XCTAssertNil(ItemAttributes.empty.condition)
    }

    func testSortingKeepsCurrenciesSeparateAndUnknownValuesLast() throws {
        let store = try ModelContainer(for: Garment.self, Look.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let unknown = Garment(front: Data([0])), euros = Garment(front: Data([1])), dollars = Garment(front: Data([2]))
        for item in [unknown, euros, dollars] { store.mainContext.insert(item) }
        try euros.setAttributes(ItemAttributes(tags: ["summer"], originalPrice: OriginalPrice(amount: "100", currency: "EUR", source: .user, evidence: "")))
        try dollars.setAttributes(ItemAttributes(tags: ["casual"], originalPrice: OriginalPrice(amount: "5", currency: "USD", source: .user, evidence: ""), condition: ConditionAssessment(grade: .good, source: .user, evidence: "")))
        XCTAssertEqual(WardrobeFilter(sort: .price).ordered([unknown, dollars, euros]).map(\.id), [euros.id, dollars.id, unknown.id])
        XCTAssertEqual(WardrobeFilter(sort: .tags).ordered([unknown, euros, dollars]).map(\.id), [dollars.id, euros.id, unknown.id])
        XCTAssertEqual(WardrobeFilter(sort: .condition).ordered([unknown, euros, dollars]).first?.id, dollars.id)
        withExtendedLifetime(store) {}
    }

    func testEditsAndAIResultsMergeWithoutOverwritingEachOther() throws {
        let initial = ItemAttributes.empty
        var generated = ItemAttributes(typeDetail: "Fedora", tags: ["summer"],
            originalPrice: OriginalPrice(amount: "100", currency: "EUR", source: .photo, evidence: "EUR 100"),
            condition: ConditionAssessment(grade: .excellent, source: .photo, evidence: "No visible wear"))
        var current = initial
        current.tags = ["mine"]
        current.originalPrice = OriginalPrice(amount: "45", currency: "EUR", source: .user, evidence: "")
        current.fillMissing(from: generated, unchangedSince: initial)
        XCTAssertEqual(current.tags, ["mine"]); XCTAssertEqual(current.originalPrice?.amount, "45")
        XCTAssertEqual(current.typeDetail, "Fedora"); XCTAssertEqual(current.condition, generated.condition)
        var edited = initial; edited.tags = ["holiday"]
        generated.applyEdits(edited, comparedTo: initial)
        XCTAssertEqual(generated.tags, ["holiday"])
        XCTAssertEqual(generated.originalPrice?.amount, "100")
        XCTAssertEqual(generated.condition?.grade, .excellent)
        generated.applyEdits(initial, comparedTo: initial, categoryChanged: true)
        XCTAssertEqual(generated.typeDetail, "")
        XCTAssertEqual(generated.tags, ["holiday"])
    }

    func testCategoryEditDuringAnalysisCannotReceiveAnIncompatibleSubtype() {
        let initial = ItemDetails.empty
        var current = initial; current.category = .tops
        var generated = initial; generated.category = .accessories; generated.subcategory = "Hats"
        current.fillMissing(from: generated, unchangedSince: initial)
        XCTAssertEqual(current.category, .tops); XCTAssertEqual(current.subcategory, "")
    }
}
