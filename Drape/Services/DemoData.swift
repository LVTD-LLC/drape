import SwiftData
import UIKit

/// Deterministic fixtures for UI tests; never added to a normal wardrobe.
@MainActor enum DemoData {
    static func photo(color: UIColor, symbol: String) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 800))
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 800))
            let configuration = UIImage.SymbolConfiguration(pointSize: 330, weight: .ultraLight)
            let image = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(color, renderingMode: .alwaysOriginal)
            image?.draw(in: CGRect(x: 115, y: 180, width: 410, height: 410))
        }
    }
    static func seed(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<Garment>()) == 0 else { return }
        let fixtures: [(String, Category, String, String, UIColor)] = [
            ("Everyday linen shirt", .tops, "Oat", "tshirt.fill", UIColor(red: 0.75, green: 0.66, blue: 0.53, alpha: 1)),
            ("Weekend denim", .bottoms, "Indigo", "figure.walk", .systemIndigo),
            ("Favorite cardigan", .outerwear, "Sage", "jacket.fill", .systemMint),
            ("City carryall", .bags, "Chocolate", "handbag.fill", .brown),
            ("Everyday sneakers", .shoes, "Cream", "shoe.fill", .lightGray),
            ("Summer shades", .accessories, "Tortoise", "sunglasses.fill", .brown)
        ]
        for (name, category, color, symbol, uiColor) in fixtures {
            var details = ItemDetails(); details.name = name; details.category = category; details.color = color
            let image = photo(color: uiColor, symbol: symbol)
            let item = Garment(front: image, details: details); item.thumbnail = ImageTools.thumbnail(image)
            context.insert(item)
        }
        try context.save()
    }
}
