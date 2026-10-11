import Foundation

enum EvidenceSource: String, Codable, Sendable {
    case photo, user
}

enum ItemCondition: String, Codable, CaseIterable, Identifiable, Sendable {
    case excellent = "Excellent", veryGood = "Very good", good = "Good", fair = "Fair", poor = "Poor"
    var id: String { rawValue }
    var rank: Int { Self.allCases.firstIndex(of: self)! }
}

struct OriginalPrice: Codable, Equatable, Sendable {
    // Decimal text avoids floating-point rounding and never assumes a currency.
    var amount: String
    var currency: String
    var source: EvidenceSource
    var evidence: String
    var decimal: Decimal? { Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) }
    var formatted: String {
        guard let decimal else { return "" }
        return "\(currency) \(NSDecimalNumber(decimal: decimal).stringValue)"
    }
    func validate() throws {
        guard amount.range(of: #"^(0|[1-9][0-9]{0,11})(\.[0-9]{1,4})?$"#, options: .regularExpression) != nil,
              decimal != nil, Locale.commonISOCurrencyCodes.contains(currency),
              source != .photo || !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AttributeError.invalidPrice
        }
    }
}

struct ConditionAssessment: Codable, Equatable, Sendable {
    var grade: ItemCondition
    var source: EvidenceSource
    var evidence: String
    var label: String { grade.rawValue + (source == .photo ? " · AI estimate" : "") }
}

struct ItemAttributes: Codable, Equatable, Sendable {
    var typeDetail = ""
    var tags: [String] = []
    var originalPrice: OriginalPrice?
    var condition: ConditionAssessment?
    static let empty = ItemAttributes()

    static func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }.filter { !$0.isEmpty })).sorted()
    }
    func validated() throws -> Self {
        var result = self
        result.tags = Self.normalizedTags(tags)
        result.typeDetail = typeDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.tags.count <= 20, result.tags.allSatisfy({ $0.count <= 40 && !$0.contains(",") }),
              result.typeDetail.count <= 120 else { throw AttributeError.invalidTags }
        try result.originalPrice?.validate()
        if let condition, condition.source == .photo && condition.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AttributeError.missingConditionEvidence
        }
        return result
    }
    mutating func fillMissing(from generated: Self, unchangedSince initial: Self) {
        if typeDetail == initial.typeDetail && initial.typeDetail.isEmpty { typeDetail = generated.typeDetail }
        if tags == initial.tags && initial.tags.isEmpty { tags = generated.tags }
        if originalPrice == initial.originalPrice && initial.originalPrice == nil { originalPrice = generated.originalPrice }
        if condition == initial.condition && initial.condition == nil { condition = generated.condition }
    }
    mutating func applyEdits(_ edited: Self, comparedTo baseline: Self, categoryChanged: Bool = false) {
        if categoryChanged || edited.typeDetail != baseline.typeDetail { typeDetail = edited.typeDetail }
        if edited.tags != baseline.tags { tags = edited.tags }
        if edited.originalPrice != baseline.originalPrice { originalPrice = edited.originalPrice }
        if edited.condition != baseline.condition { condition = edited.condition }
    }
    var searchableText: String {
        ([typeDetail, originalPrice?.formatted ?? "", condition?.grade.rawValue ?? ""] + tags).joined(separator: " ")
    }
}

struct ItemAnalysis: Codable, Equatable, Sendable {
    var details: ItemDetails
    var attributes: ItemAttributes = .empty
}

enum AttributeError: LocalizedError {
    case invalidPrice, invalidTags, missingConditionEvidence
    var errorDescription: String? {
        switch self {
        case .invalidPrice: "Enter a non-negative price and a valid three-letter currency, such as EUR or USD."
        case .invalidTags: "Use up to 20 tags of 40 characters each and a specific style of up to 120 characters."
        case .missingConditionEvidence: "A photo-based condition estimate needs a description of the visible wear."
        }
    }
}

enum ItemTaxonomy {
    static func types(in category: Category) -> [String] {
        switch category {
        case .tops: ["T-shirts", "Shirts", "Blouses", "Tank tops", "Sweaters", "Cardigans", "Hoodies", "Sweatshirts"]
        case .bottoms: ["Jeans", "Trousers", "Shorts", "Skirts", "Leggings"]
        case .dresses: ["Dresses", "Jumpsuits", "Playsuits"]
        case .outerwear: ["Coats", "Jackets", "Blazers", "Vests", "Raincoats"]
        case .shoes: ["Sneakers", "Boots", "Sandals", "Heels", "Flats", "Loafers", "Slippers"]
        case .bags: ["Handbags", "Shoulder bags", "Crossbody bags", "Totes", "Backpacks", "Clutches", "Wallets"]
        case .accessories: ["Hats", "Rings", "Necklaces", "Watches", "Bracelets", "Earrings", "Brooches", "Scarves", "Belts", "Gloves", "Sunglasses", "Ties", "Hair accessories"]
        case .other: ["Underwear", "Socks", "Swimwear", "Sleepwear", "Other"]
        }
    }
    // Read-only classification: preserve the original free-text subtype in shipped stores.
    static func type(for details: ItemDetails) -> String {
        let raw = details.subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = raw.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        let aliases: [(String, [String])] = [
            ("Hats", ["hat", "hats", "cap", "caps", "beanie", "fedora", "beret"]),
            ("Rings", ["ring", "rings"]), ("Necklaces", ["necklace", "necklaces", "pendant"]),
            ("Watches", ["watch", "watches", "smartwatch"]), ("Bracelets", ["bracelet", "bracelets", "bangle"]),
            ("Earrings", ["earring", "earrings"]), ("Scarves", ["scarf", "scarves", "shawl"])
        ]
        for type in types(in: details.category) where type.caseInsensitiveCompare(raw) == .orderedSame { return type }
        for (type, terms) in aliases where types(in: details.category).contains(type) && words.contains(where: terms.contains) { return type }
        for type in types(in: details.category) {
            let singular = type.lowercased().hasSuffix("s") ? String(type.lowercased().dropLast()) : type.lowercased()
            if raw.lowercased() == singular || words.contains(singular) { return type }
        }
        return raw.isEmpty ? "Unspecified" : raw
    }
    static var prompt: String {
        Category.allCases.map { "\($0.rawValue): \(types(in: $0).joined(separator: ", "))" }.joined(separator: "; ")
    }
}

enum WardrobeSort: String, CaseIterable, Identifiable {
    case newest = "Newest first", oldest = "Oldest first", name = "Name", type = "Item type"
    case tags = "Tags", condition = "Condition", price = "Original price (by currency)"
    var id: String { rawValue }
}

struct WardrobeFilter {
    var category: Category?
    var type: String?
    var tags: Set<String> = []
    var condition: ItemCondition?
    var favoritesOnly = false
    var sort: WardrobeSort = .newest

    func matches(details: ItemDetails, attributes: ItemAttributes, favorite: Bool, search: String) -> Bool {
        (category == nil || details.category == category) &&
        (type == nil || ItemTaxonomy.type(for: details) == type) &&
        tags.isSubset(of: Set(attributes.tags)) &&
        (condition == nil || attributes.condition?.grade == condition) &&
        (!favoritesOnly || favorite) &&
        (search.isEmpty || (details.searchableText + " " + attributes.searchableText).localizedCaseInsensitiveContains(search))
    }
    @MainActor func ordered(_ items: [Garment]) -> [Garment] {
        items.sorted { a, b in
            let aa = a.attributes, ba = b.attributes
            switch sort {
            case .newest: if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            case .oldest: if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            case .name:
                if a.displayName != b.displayName { return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending }
            case .type:
                let ak = a.details.category.rawValue + ItemTaxonomy.type(for: a.details)
                let bk = b.details.category.rawValue + ItemTaxonomy.type(for: b.details)
                if ak != bk { return ak.localizedStandardCompare(bk) == .orderedAscending }
            case .tags:
                if aa.tags.isEmpty != ba.tags.isEmpty { return !aa.tags.isEmpty }
                if aa.tags != ba.tags { return aa.tags.joined(separator: ",") < ba.tags.joined(separator: ",") }
            case .condition:
                let ar = aa.condition?.grade.rank ?? Int.max, br = ba.condition?.grade.rank ?? Int.max
                if ar != br { return ar < br }
            case .price:
                if let ap = aa.originalPrice, let bp = ba.originalPrice {
                    if ap.currency != bp.currency { return ap.currency < bp.currency }
                    if let av = ap.decimal, let bv = bp.decimal, av != bv { return av < bv }
                } else if (aa.originalPrice == nil) != (ba.originalPrice == nil) { return aa.originalPrice != nil }
            }
            return a.id.uuidString < b.id.uuidString
        }
    }
}
