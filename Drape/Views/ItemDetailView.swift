import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: Garment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProcessingCoordinator.self) private var processor
    @AppStorage("analysisModel") private var analysisModel = "google/gemini-2.5-flash"
    @AppStorage("imageModel") private var imageModel = "google/gemini-2.5-flash-image"
    @AppStorage("studioEnabled") private var studioEnabled = false
    @State private var editing = false
    @State private var reviewing = false
    @State private var deleting = false
    @State private var consent = false
    @State private var error: String?
    @State private var selectedPhoto = "Catalogue"
    private var busy: Bool { processor.activeIDs.contains(item.id) }
    private var photoChoices: [String] {
        ["Catalogue", "Original"] + (item.back == nil ? [] : ["Back"]) + (item.label == nil ? [] : ["Label"]) + (item.studio == nil ? [] : ["Studio"])
    }
    private var photo: Data {
        switch selectedPhoto {
        case "Original": item.front
        case "Back": item.back ?? item.front
        case "Label": item.label ?? item.front
        case "Studio": item.studio ?? item.front
        default: item.displayPhoto
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GarmentImage(data: photo).frame(height: 370).clipShape(RoundedRectangle(cornerRadius: 24))
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(photoChoices, id: \.self) { choice in
                            Button(choice) { selectedPhoto = choice }.buttonStyle(.bordered)
                                .tint(selectedPhoto == choice ? Style.accent : .secondary)
                        }
                    }
                }.scrollIndicators(.hidden)
                if selectedPhoto == "Studio" || (selectedPhoto == "Catalogue" && item.useStudio) {
                    Label("AI-generated preview. Compare with the original for accurate details.", systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.secondary)
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
                if item.suggestions != nil {
                    Button { reviewing = true } label: { Label("Review AI suggestions", systemImage: "sparkles") }.buttonStyle(PrimaryButton())
                }
                if !busy && !item.processingMessage.isEmpty {
                    Text(item.processingMessage).font(.footnote).foregroundStyle(.secondary).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
                if item.studio != nil {
                    Toggle("Use studio photo in wardrobe", isOn: Binding(get: { item.useStudio }, set: { value in
                        let old = item.useStudio
                        item.useStudio = value; item.thumbnail = ImageTools.thumbnail(item.displayPhoto)
                        do { try context.save() } catch {
                            item.useStudio = old; item.thumbnail = ImageTools.thumbnail(item.displayPhoto); self.error = error.localizedDescription
                        }
                    })).font(.subheadline)
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
                if !item.labelText.isEmpty {
                    DisclosureGroup("Text from the label") { Text(item.labelText).font(.footnote).textSelection(.enabled).padding(.top, 8) }
                }
                HStack {
                    Button { processor.start(item, context: context) } label: { Label("Prepare photo", systemImage: "photo.badge.checkmark") }
                        .buttonStyle(.bordered)
                    Button { consent = true } label: { Label("Ask AI", systemImage: "sparkles") }.buttonStyle(.borderedProminent)
                }.disabled(busy)
                Text("Prepare photo removes the background on your iPhone when supported. Ask AI suggests details and can create a studio photo using OpenRouter.")
                    .font(.caption).foregroundStyle(.secondary)
                if let model = item.analysisModel { Text("Details suggested by \(model)").font(.caption2).foregroundStyle(.tertiary) }
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
        .sheet(isPresented: $reviewing) {
            if let suggestions = item.suggestions {
                DetailsEditor(details: suggestions, reviewing: true) { details in
                    let old = item.details; item.details = details; item.suggestions = nil
                    do { try context.save() } catch { item.details = old; item.suggestions = suggestions; throw error }
                }
            }
        }
        .confirmationDialog("Delete this piece and its photos?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete piece", role: .destructive) { delete() }
        } message: { Text("It will also be removed from your looks. This cannot be undone.") }
        .alert("Send photos to OpenRouter?", isPresented: $consent) {
            Button("Send photos") { askAI() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The front, back and label photos will be sent to OpenRouter and your selected model providers. Their data policies apply. This uses your OpenRouter credits.\(studioEnabled ? " A studio photo will also be generated." : "") Your current details won’t change until you accept the suggestions.")
        }
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
    private func askAI() {
        do {
            let key = try Keychain.read()
            guard !key.isEmpty else { throw AIError.missingKey }
            processor.start(item, context: context, configuration: AIConfiguration(key: key, analysisModel: analysisModel, imageModel: imageModel, generateStudio: studioEnabled))
        } catch { self.error = error.localizedDescription }
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
