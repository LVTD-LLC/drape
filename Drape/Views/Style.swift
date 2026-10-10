import SwiftUI

 enum Style {
    static let accent = Color("AccentColor")
    static let canvas = Color("Canvas")
    static let title = Font.system(.largeTitle, design: .serif).weight(.regular)
 }

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundStyle(Color.white).background(Style.accent.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4), in: Capsule())
    }
}

struct GarmentImage: View {
    let data: Data?
    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "tshirt").font(.largeTitle).foregroundStyle(.gray)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
    }
}

struct ItemCard: View {
    let item: Garment
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            GarmentImage(data: item.thumbnail ?? item.displayPhoto).frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .topTrailing) {
                    if item.isFavorite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(Style.accent).padding(10).background(.regularMaterial, in: Circle()).padding(8) }
                }
            Text(item.displayName).font(.subheadline.weight(.medium)).lineLimit(2).foregroundStyle(.primary)
            Text([item.details.color, item.details.subcategory.isEmpty ? item.details.category.rawValue : item.details.subcategory]
                .filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if item.processingState == "processing" {
                Label("Preparing", systemImage: "sparkles").font(.caption2).foregroundStyle(Style.accent)

            }
        }.accessibilityElement(children: .combine)
    }
}

struct ErrorNotice: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.alert("Something needs attention", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }
}
extension View {
    func errorNotice(_ message: Binding<String?>) -> some View { modifier(ErrorNotice(message: message)) }
}
