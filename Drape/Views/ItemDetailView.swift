import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: Garment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProcessingCoordinator.self) private var processor
    @State private var editing = false
    @State private var deleting = false
    @State private var error: String?
    @State private var selectedPhoto = 0
    private var busy: Bool { processor.activeIDs.contains(item.id) }
    private var photos: [Data] {
        [item.studio ?? item.cutout].compactMap { $0 } + item.sourcePhotos
    }
    private var photoLabel: String {
        let hasCover = item.studio != nil || item.cutout != nil
        if hasCover && selectedPhoto == 0 { return item.studio == nil ? "Your piece" : "Studio · AI generated" }
        return "Original \(selectedPhoto + (hasCover ? 0 : 1))"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 10) {
                    TabView(selection: $selectedPhoto) {
                        ForEach(photos.indices, id: \.self) { index in
                            GarmentImage(data: photos[index]).tag(index)
                                .accessibilityLabel(index == 0 && item.studio != nil ? "Studio photo" : "Photo \(index + 1)")
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: 390).clipShape(RoundedRectangle(cornerRadius: 24))
                        .accessibilityIdentifier("photoCarousel")
                    Text("\(photoLabel) · \(selectedPhoto + 1) of \(photos.count)")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("photoPosition")
                    if photos.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(photos.indices, id: \.self) { index in
                                Circle().fill(index == selectedPhoto ? Style.accent : Style.accent.opacity(0.2)).frame(width: 6, height: 6)
                            }
                        }.accessibilityHidden(true)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.displayName).font(Style.title)
                    Text([item.details.brand, item.details.color, item.details.category.rawValue].filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
                if busy {
                    HStack(spacing: 12) { ProgressView(); Text(item.processingMessage).font(.subheadline) }
                    Text("Keep Drape open while it prepares your piece.").font(.caption).foregroundStyle(.secondary)
                }
                if !busy && !item.processingMessage.isEmpty {
                    Text(item.processingMessage).font(.footnote).foregroundStyle(.secondary).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
                VStack(spacing: 0) {
                    detail("Type", item.details.subcategory.isEmpty ? item.details.category.rawValue : item.details.subcategory)
                    detail("Color", item.details.color)
                    detail("Brand", item.details.brand)
                    detail("Size", item.details.size)
                    detail("Material", item.details.material)
                    detail("Pattern", item.details.pattern)
                    detail("Season", item.details.season)
                    detail("Care", item.details.care)
                }.padding(.horizontal, 16).background(.background, in: RoundedRectangle(cornerRadius: 18))
                if !item.details.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) { Text("Notes").font(.headline); Text(item.details.notes).foregroundStyle(.secondary) }
                }
                if !busy && item.needsAI {
                    Button("Finish preparing") { processor.start(item, context: context, configuration: .automatic) }
                        .buttonStyle(.bordered)
                    Text("Sends photos to Drape’s AI providers to complete missing details or the studio photo. Completed steps won’t run again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(22)
        }.background(Style.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button(item.isFavorite ? "Remove favorite" : "Favorite", systemImage: item.isFavorite ? "heart.fill" : "heart") {
                item.isFavorite.toggle()
                do { try context.save() } catch { item.isFavorite.toggle(); self.error = error.localizedDescription }
            } }
            ToolbarItem(placement: .topBarTrailing) { Menu {
                Button("Edit details", systemImage: "pencil") { editing = true }.accessibilityIdentifier("editDetails")
                Button("Delete piece", systemImage: "trash", role: .destructive) { deleting = true }
            } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Piece options") }
        }
        .sheet(isPresented: $editing) {
            DetailsEditor(details: item.details) { details in
                let old = item.details; item.details = details
                do { try context.save() } catch { item.details = old; throw error }
            }
        }
        .confirmationDialog("Delete this piece and its photos?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete piece", role: .destructive) { delete() }
        } message: { Text("It will also be removed from your looks. This cannot be undone.") }
        .errorNotice($error)
    }
    @ViewBuilder private func detail(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .top) {
                Text(title).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
                Text(value).frame(maxWidth: .infinity, alignment: .trailing)
            }.font(.subheadline).padding(.vertical, 12)
        }
    }
    private func delete() {
        processor.cancel(item.id)
        do {
            for look in try context.fetch(FetchDescriptor<Look>()) { look.garmentIDs.removeAll { $0 == item.id } }
            context.delete(item)
            try context.save(); dismiss()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}
