import SwiftUI

struct DetailsFields: View {
    @Binding var details: ItemDetails
    var body: some View {
        Section("The essentials") {
            TextField("Name", text: $details.name).accessibilityIdentifier("editName")
            Picker("Category", selection: $details.category) { ForEach(Category.allCases) { Text($0.rawValue).tag($0) } }
                .accessibilityIdentifier("editCategory")
                .onChange(of: details.category) { _, _ in details.subcategory = "" }
            Picker("Item type", selection: $details.subcategory) {
                Text("Unspecified").tag("")
                ForEach(ItemTaxonomy.types(in: details.category), id: \.self) { Text($0).tag($0) }
                if !details.subcategory.isEmpty && !ItemTaxonomy.types(in: details.category).contains(details.subcategory) {
                    Text(details.subcategory).tag(details.subcategory)
                }
            }.accessibilityIdentifier("editItemType")
            TextField("Color", text: $details.color)
            TextField("Pattern", text: $details.pattern)
        }
        Section("From the label") {
            TextField("Brand", text: $details.brand)
            TextField("Size", text: $details.size)
            TextField("Material", text: $details.material)
            TextField("Care instructions", text: $details.care, axis: .vertical).lineLimit(2...5)
        }
        Section("A little more") {
            TextField("Season", text: $details.season)
            TextField("Notes", text: $details.notes, axis: .vertical).lineLimit(3...8)
        }
    }
}

struct DetailsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var details: ItemDetails
    @State var attributes: ItemAttributes
    let onSave: (ItemDetails, ItemAttributes) throws -> Void
    @State private var tagsText: String
    @State private var priceAmount: String
    @State private var priceCurrency: String
    @State private var condition: ItemCondition?
    @State private var conditionNotes: String
    @State private var error: String?

    init(details: ItemDetails, attributes: ItemAttributes, onSave: @escaping (ItemDetails, ItemAttributes) throws -> Void) {
        _details = State(initialValue: details)
        _attributes = State(initialValue: attributes)
        _tagsText = State(initialValue: attributes.tags.joined(separator: ", "))
        _priceAmount = State(initialValue: attributes.originalPrice?.amount ?? "")
        _priceCurrency = State(initialValue: attributes.originalPrice?.currency ?? "")
        _condition = State(initialValue: attributes.condition?.grade)
        _conditionNotes = State(initialValue: attributes.condition?.evidence ?? "")
        self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                DetailsFields(details: $details)
                Section {
                    TextField("Specific style (e.g. wide-brim hat)", text: $attributes.typeDetail)
                        .accessibilityIdentifier("editTypeDetail")
                    TextField("Tags, separated by commas", text: $tagsText, axis: .vertical)
                        .textInputAutocapitalization(.never).accessibilityIdentifier("editTags")
                } header: { Text("Style & tags") } footer: {
                    Text("Tags help you find pieces: minimalist, work, summer, floral. Use up to 20.")
                }
                Section {
                    TextField("Amount", text: $priceAmount).keyboardType(.decimalPad).accessibilityIdentifier("editPrice")
                    TextField("Currency (EUR, USD…)", text: $priceCurrency).textInputAutocapitalization(.characters)
                        .autocorrectionDisabled().accessibilityIdentifier("editCurrency")
                    if let price = attributes.originalPrice, price.source == .photo {
                        Text("Read from photo: \(price.evidence)").font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Original price") } footer: {
                    Text("Enter the original price, or leave it blank. Drape only reads prices clearly shown in photos; it never estimates their value.")
                }
                Section {
                    Picker("Condition", selection: $condition) {
                        Text("Unknown").tag(nil as ItemCondition?)
                        ForEach(ItemCondition.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }.accessibilityIdentifier("editCondition")
                    TextField("Visible wear or condition notes", text: $conditionNotes, axis: .vertical).lineLimit(2...4)
                } header: { Text("Condition") } footer: {
                    Text(attributes.condition?.source == .photo
                         ? "AI estimate from visible photos. Hidden wear and functionality cannot be assessed. Edit to correct it."
                         : "Excellent means no visible wear; Poor means heavy wear or damage. Leave unknown when unsure.")
                }
            }
            .onChange(of: details.category) { _, _ in attributes.typeDetail = "" }
            .navigationTitle("Edit piece").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    do { try onSave(details, editedAttributes()); dismiss() } catch { self.error = error.localizedDescription }
                }.fontWeight(.semibold).accessibilityIdentifier("saveDetails") }
            }.errorNotice($error)
        }
    }

    private func editedAttributes() throws -> ItemAttributes {
        var edited = attributes
        edited.tags = ItemAttributes.normalizedTags(tagsText.components(separatedBy: ","))
        let amount = priceAmount.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let currency = priceCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if amount.isEmpty { edited.originalPrice = nil }
        else if amount != attributes.originalPrice?.amount || currency != attributes.originalPrice?.currency {
            edited.originalPrice = OriginalPrice(amount: amount, currency: currency, source: .user, evidence: "")
        }
        if condition != attributes.condition?.grade || conditionNotes != (attributes.condition?.evidence ?? "") {
            edited.condition = condition.map { ConditionAssessment(grade: $0, source: .user, evidence: conditionNotes) }
        }
        return try edited.validated()
    }
}
