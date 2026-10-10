import SwiftUI
import SwiftData

struct LooksView: View {
    @Query(sort: \Look.createdAt, order: .reverse) private var looks: [Look]
    @Query private var garments: [Garment]
    @Environment(\.modelContext) private var context
    @State private var adding = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Better together.").font(Style.title)
                    Text("Little combinations for whatever’s ahead.").foregroundStyle(.secondary)
                    if looks.isEmpty {
                        ContentUnavailableView {
                            Label("Your next look starts here", systemImage: "rectangle.on.rectangle.angled")
                        } description: { Text("Choose pieces from your wardrobe and save an outfit for another day.") }
                        Button("Create a look") { adding = true }.buttonStyle(PrimaryButton()).disabled(garments.isEmpty)
                        if garments.isEmpty { Text("Add your first piece in Wardrobe to get started.").font(.footnote).foregroundStyle(.secondary) }
                    }
                    ForEach(looks) { look in
                        NavigationLink { LookDetailView(look: look) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    ForEach(Array(garments.filter { look.garmentIDs.contains($0.id) }.prefix(3))) { item in
                                        GarmentImage(data: item.thumbnail ?? item.displayPhoto).frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                }
                                Text(look.name).font(.system(.title2, design: .serif)).foregroundStyle(.primary)
                                Text("\(look.garmentIDs.count) pieces").font(.caption).foregroundStyle(.secondary)
                            }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain)
                    }
                }.padding(22)
            }.background(Style.canvas).navigationTitle("Looks").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("New look", systemImage: "plus") { adding = true }.disabled(garments.isEmpty) } }
            .sheet(isPresented: $adding) { LookEditor() }
            .errorNotice($error)
        }
    }
}

struct LookDetailView: View {
    @Bindable var look: Look
    @Query private var garments: [Garment]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(look.name).font(Style.title)
                if !look.notes.isEmpty { Text(look.notes).foregroundStyle(.secondary) }
                if look.garmentIDs.isEmpty { Text("The pieces in this look have been removed. Edit it to choose some more.").foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 16)], spacing: 24) {
                    ForEach(garments.filter { look.garmentIDs.contains($0.id) }) { item in
                        NavigationLink { ItemDetailView(item: item) } label: { ItemCard(item: item) }.buttonStyle(.plain)
                    }
                }
            }.padding(22)
        }.background(Style.canvas).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu {
            Button("Edit look", systemImage: "pencil") { editing = true }
            Button("Delete look", systemImage: "trash", role: .destructive) { deleting = true }
        } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Look options") } }
        .sheet(isPresented: $editing) { LookEditor(look: look) }
        .confirmationDialog("Delete this look?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete look", role: .destructive) {
                context.delete(look)
                do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
            }
        } message: { Text("The clothing in your wardrobe will be kept.") }
        .errorNotice($error)
    }
}

struct LookEditor: View {
    var look: Look?
    @Query(sort: \Garment.createdAt, order: .reverse) private var garments: [Garment]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var notes = ""
    @State private var selected: Set<UUID> = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("The occasion") {
                    TextField("Name your look", text: $name).accessibilityIdentifier("lookName")
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                }
                Section("Choose your pieces · \(selected.count) selected") {
                    ForEach(garments) { item in
                        Button {
                            if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                        } label: {
                            HStack(spacing: 14) {
                                GarmentImage(data: item.thumbnail ?? item.displayPhoto).frame(width: 55, height: 65).clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(item.displayName).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Style.accent)
                            }
                        }.accessibilityAddTraits(selected.contains(item.id) ? .isSelected : [])
                    }
                }
            }.navigationTitle(look == nil ? "New look" : "Edit look").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selected.isEmpty).accessibilityIdentifier("saveLook") }
            }
            .onAppear { if let look { name = look.name; notes = look.notes; selected = Set(look.garmentIDs) } }
            .errorNotice($error)
        }
    }
    private func save() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let look { look.name = title; look.notes = notes; look.garmentIDs = Array(selected) }
        else { context.insert(Look(name: title, notes: notes, garmentIDs: Array(selected))) }
        do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
    }
}
