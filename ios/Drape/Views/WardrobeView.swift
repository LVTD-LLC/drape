import SwiftUI
import SwiftData

struct WardrobeView: View {
    @Query(sort: \Garment.createdAt, order: .reverse) private var items: [Garment]
    @State private var search = ""
    @State private var filter = WardrobeFilter()
    @State private var filtering = false
    @State private var grouped = false
    @State private var adding = false
    private var filtered: [Garment] {
        filter.ordered(items.filter { filter.matches(details: $0.details, attributes: $0.attributes, favorite: $0.isFavorite, search: search) })
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
                        Button { filtering = true } label: { Image(systemName: "line.3.horizontal.decrease").padding(10) }
                            .accessibilityLabel("Filter and group wardrobe")
                    }.padding(.horizontal, 22)
                    if !items.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                categoryButton("All pieces", value: nil)
                                ForEach(Category.allCases) { categoryButton($0.rawValue, value: $0) }
                            }.padding(.horizontal, 22)
                        }.scrollIndicators(.hidden)
                        if filter.type != nil || !filter.tags.isEmpty || filter.condition != nil || filter.favoritesOnly {
                            HStack {
                                Text("\(filtered.count) matching \(filtered.count == 1 ? "piece" : "pieces")").foregroundStyle(.secondary)
                                Spacer()
                                Button("Clear filters") { filter = WardrobeFilter() }
                            }.font(.subheadline).padding(.horizontal, 22)
                        }
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
            .searchable(text: $search, prompt: "Find a piece, type, or tag")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add piece", systemImage: "plus") { adding = true }.accessibilityIdentifier("addPiece")
                }
            }
            .sheet(isPresented: $adding) { AddItemView() }
            .sheet(isPresented: $filtering) { WardrobeFilters(filter: $filter, grouped: $grouped, items: items) }
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
        Button { filter.category = value; filter.type = nil } label: {
            Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                .background(filter.category == value ? Style.accent : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(filter.category == value ? Color.white : Color.primary)
        }.buttonStyle(.plain).accessibilityAddTraits(filter.category == value ? .isSelected : [])
    }
}

private struct WardrobeFilters: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: WardrobeFilter
    @Binding var grouped: Bool
    let items: [Garment]
    private var types: [String] {
        let categories = filter.category.map { [$0] } ?? Category.allCases
        let existing = items.filter { filter.category == nil || $0.details.category == filter.category }.map { ItemTaxonomy.type(for: $0.details) }
        return Array(Set(categories.flatMap(ItemTaxonomy.types) + existing)).sorted()
    }
    private var tags: [String] { Array(Set(items.flatMap { $0.attributes.tags }).union(filter.tags)).sorted() }
    var body: some View {
        NavigationStack {
            Form {
                Section("Find your pieces") {
                    Picker("Category", selection: $filter.category) {
                        Text("All categories").tag(nil as Category?)
                        ForEach(Category.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }.onChange(of: filter.category) { _, _ in filter.type = nil }
                    Picker("Item type", selection: $filter.type) {
                        Text("All types").tag(nil as String?)
                        ForEach(types, id: \.self) { Text($0).tag(Optional($0)) }
                    }.accessibilityIdentifier("filterItemType")
                    Picker("Condition", selection: $filter.condition) {
                        Text("Any condition").tag(nil as ItemCondition?)
                        ForEach(ItemCondition.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Toggle("Favorites only", isOn: $filter.favoritesOnly)
                }
                Section {
                    if tags.isEmpty { Text("Tags will appear here when you add them to a piece.").foregroundStyle(.secondary) }
                    ForEach(tags, id: \.self) { tag in
                        Toggle(tag, isOn: Binding(get: { filter.tags.contains(tag) }, set: { selected in
                            if selected { filter.tags.insert(tag) } else { filter.tags.remove(tag) }
                        })).accessibilityIdentifier("filterTag-\(tag)")
                    }
                } header: { Text("Tags") } footer: { Text("Pieces must match every selected tag.") }
                Section {
                    Picker("Sort by", selection: $filter.sort) { ForEach(WardrobeSort.allCases) { Text($0.rawValue).tag($0) } }
                        .accessibilityIdentifier("sortWardrobe")
                    Toggle("Group by category", isOn: $grouped)
                } header: { Text("Display") } footer: {
                    Text("Price sorts from low to high within each currency. Condition sorts from excellent to poor. Unknown values appear last.")
                }
                Button("Reset filters") { filter = WardrobeFilter(); grouped = false }
            }
            .navigationTitle("Filter & sort").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
