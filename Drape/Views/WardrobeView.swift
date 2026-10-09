import SwiftUI
import SwiftData

struct WardrobeView: View {
    @Query(sort: \Garment.createdAt, order: .reverse) private var items: [Garment]
    @State private var search = ""
    @State private var category: Category?
    @State private var favoritesOnly = false
    @State private var grouped = false
    @State private var adding = false
    private var filtered: [Garment] {
        items.filter { item in
            (category == nil || item.details.category == category) && (!favoritesOnly || item.isFavorite) &&
            (search.isEmpty || item.details.searchableText.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Your wardrobe").font(Style.title)
                            Text(items.isEmpty ? "Good things, kept close." : "\(items.count) \(items.count == 1 ? "piece" : "pieces"), endless possibilities.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Toggle("Favorites only", isOn: $favoritesOnly)
                            Toggle("Group by type", isOn: $grouped)
                        } label: { Image(systemName: "line.3.horizontal.decrease").padding(10) }
                            .accessibilityLabel("Filter and group wardrobe")
                    }.padding(.horizontal, 22)
                    if !items.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                categoryButton("All pieces", value: nil)
                                ForEach(Category.allCases) { categoryButton($0.rawValue, value: $0) }
                            }.padding(.horizontal, 22)
                        }.scrollIndicators(.hidden)
                    }
                    if items.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "tshirt").font(.system(size: 65, weight: .ultraLight)).foregroundStyle(Style.accent).padding(35)
                                .background(Style.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 32))
                            Text("Start with a favorite.").font(.system(.title2, design: .serif))
                            Text("The shirt you reach for. The perfect pair of jeans. One photo is all it takes.")
                                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 285)
                            Button("Add your first piece") { adding = true }.buttonStyle(PrimaryButton()).padding(.top, 8)
                        }.padding(28).padding(.top, 28)
                    } else if filtered.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else if grouped {
                        ForEach(Category.allCases) { type in
                            let group = filtered.filter { $0.details.category == type }
                            if !group.isEmpty {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text(type.rawValue).font(.system(.title2, design: .serif))
                                    grid(group)
                                }.padding(.horizontal, 22)
                            }
                        }
                    } else {
                        grid(filtered).padding(.horizontal, 22)
                    }
                }.padding(.top, 16).padding(.bottom, 30)
            }
            .background(Style.canvas)
            .navigationTitle("drape").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Find a piece, color, or brand")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add piece", systemImage: "plus") { adding = true }.accessibilityIdentifier("addPiece")
                }
            }
            .sheet(isPresented: $adding) { AddItemView() }
            .navigationDestination(for: Garment.self) { ItemDetailView(item: $0) }
        }
    }
    private func grid(_ garments: [Garment]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 16)], alignment: .leading, spacing: 25) {
            ForEach(garments) { item in
                NavigationLink(value: item) { ItemCard(item: item) }.buttonStyle(.plain)
            }
        }
    }
    private func categoryButton(_ title: String, value: Category?) -> some View {
        Button { category = value } label: {
            Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                .background(category == value ? Style.accent : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(category == value ? Color.white : Color.primary)
        }.buttonStyle(.plain).accessibilityAddTraits(category == value ? .isSelected : [])
    }
}
