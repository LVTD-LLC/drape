import SwiftUI

struct DetailsFields: View {
    @Binding var details: ItemDetails
    var body: some View {
        Section("The essentials") {
            TextField("Name", text: $details.name).accessibilityIdentifier("editName")
            Picker("Type", selection: $details.category) { ForEach(Category.allCases) { Text($0.rawValue).tag($0) } }
            TextField("Specific type (e.g. cardigan)", text: $details.subcategory)
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
    let onSave: (ItemDetails) throws -> Void
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                DetailsFields(details: $details)
            }
            .navigationTitle("Edit piece").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    do { try onSave(details); dismiss() } catch { self.error = error.localizedDescription }
                }.fontWeight(.semibold).accessibilityIdentifier("saveDetails") }
            }.errorNotice($error)
        }
    }
}
