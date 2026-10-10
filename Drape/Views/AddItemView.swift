import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ProcessingCoordinator.self) private var processor
    @State private var photos: [PhotoRole: Data] = [:]
    @State private var role: PhotoRole = .front
    @State private var selection: PhotosPickerItem?
    @State private var camera = false
    @State private var importing = false
    @State private var name = ""
    @State private var category: Category = .other
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var consent = false
    @AppStorage("aiEnabled") private var aiEnabled = false
    @AppStorage("studioEnabled") private var studioEnabled = false
    @AppStorage("analysisModel") private var analysisModel = AIModelDefaults.analysis
    @AppStorage("imageModel") private var imageModel = AIModelDefaults.image

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Meet your next piece.").font(Style.title)
                    Text("Start with the front. Add the back for detail, and the label for size, fabric, and care.")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(PhotoRole.allCases) { photoRole in
                            Button { role = photoRole } label: {
                                VStack(spacing: 8) {
                                    Group {
                                        if let data = photos[photoRole] { GarmentImage(data: data) }
                                        else { Image(systemName: photoRole == .label ? "tag" : "tshirt").font(.title).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
                                    }.frame(height: 125).background(.background)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(role == photoRole ? Style.accent : .clear, lineWidth: 2))
                                    Text(photoRole.rawValue).font(.subheadline.weight(.medium))
                                    Text(photoRole == .front ? "Required" : "Optional").font(.caption2).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain).accessibilityLabel("\(photoRole.rawValue) photo, \(photos[photoRole] == nil ? "not added" : "added")")
                        }
                    }
                    HStack(spacing: 12) {
                        Button { Task { await openCamera() } } label: { Label("Camera", systemImage: "camera").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                        PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                            Label("Photos", systemImage: "photo").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).controlSize(.large).disabled(importing)
                    }
                    Text("Adding: \(role.rawValue.lowercased()) photo").font(.caption).foregroundStyle(.secondary)
                    if photos[role] != nil {
                        Button("Remove \(role.rawValue.lowercased()) photo", role: .destructive) { photos[role] = nil }.font(.footnote)
                    }
                    if importing { ProgressView("Preparing photo…") }
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Give it a name (optional)", text: $name).textFieldStyle(.roundedBorder).accessibilityIdentifier("itemName")
                        Picker("Type", selection: $category) { ForEach(Category.allCases) { Text($0.rawValue).tag($0) } }
                    }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 18))
                    Label("Lay one item flat or hang it in good light. Keep the whole piece in frame.", systemImage: "sun.max")
                        .font(.footnote).foregroundStyle(.secondary)
                    if aiEnabled {
                        Label("AI will suggest details\(studioEnabled ? " and a studio photo" : "") after saving. You choose what to keep.", systemImage: "sparkles").font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Add to wardrobe") {
                        if aiEnabled { consent = true } else { save(configuration: nil) }
                    }.buttonStyle(PrimaryButton()).disabled(photos[.front] == nil || importing).accessibilityIdentifier("savePiece")
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                        Button("Use test photo") { photos[.front] = DemoData.photo(color: .brown, symbol: "tshirt.fill") }.accessibilityIdentifier("testPhoto")
                    }
                    #endif
                }.padding(24)
            }.background(Style.canvas)
            .navigationTitle("New piece").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") {
                if photos.isEmpty { dismiss() } else { confirmDiscard = true }
            } } }
            .interactiveDismissDisabled(!photos.isEmpty)
            .confirmationDialog("Discard this new piece?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard photos", role: .destructive) { dismiss() }
            }
            .alert("Send photos to OpenRouter?", isPresented: $consent) {
                Button("Send and add") {
                    do {
                        let key = try Keychain.read()
                        guard !key.isEmpty else { throw AIError.missingKey }
                        save(configuration: AIConfiguration(key: key, analysisModel: analysisModel, imageModel: imageModel, generateStudio: studioEnabled))
                    } catch { self.error = error.localizedDescription }
                }
                Button("Add without AI") { save(configuration: nil) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("These photos will be sent to OpenRouter and the selected model providers for analysis\(studioEnabled ? " and image generation" : ""). Their data policies apply. Requests use your OpenRouter credits. Your originals stay on this iPhone.")
            }
            .sheet(isPresented: $camera) { CameraView { data in
                camera = false
                if let data { prepare(data, for: role) }
            }.ignoresSafeArea() }
            .onChange(of: selection) { _, selected in
                guard let selected else { return }
                let selectedRole = role
                importing = true
                Task {
                    do {
                        guard let data = try await selected.loadTransferable(type: Data.self) else { throw PhotoError.unreadable }
                        photos[selectedRole] = try await Task.detached { try ImageTools.normalized(data) }.value
                    } catch { self.error = error.localizedDescription }
                    importing = false; selection = nil
                }
            }
            .errorNotice($error)
        }
    }
    private func openCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            error = "A camera isn’t available here. Choose a photo from your library instead."; return
        }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        if granted { camera = true }
        else { error = "Camera access is off. Enable it in iPhone Settings → Drape, or choose a photo from your library." }
    }
    private func prepare(_ data: Data, for role: PhotoRole) {
        importing = true
        Task {
            defer { importing = false }
            do { photos[role] = try await Task.detached { try ImageTools.normalized(data) }.value }
            catch { self.error = error.localizedDescription }
        }
    }
    private func save(configuration: AIConfiguration?) {
        guard let front = photos[.front] else { return }
        var details = ItemDetails()
        details.name = name.trimmingCharacters(in: .whitespacesAndNewlines); details.category = category
        let item = Garment(front: front, back: photos[.back], label: photos[.label], details: details)
        item.thumbnail = ImageTools.thumbnail(front)
        context.insert(item)
        do {
            try context.save()
            processor.start(item, context: context, configuration: configuration)
            dismiss()
        } catch { context.delete(item); self.error = "Couldn’t save your piece. \(error.localizedDescription)" }
    }
}

struct CameraView: UIViewControllerRepresentable {
    let completion: (Data?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera
        picker.cameraCaptureMode = .photo; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (Data?) -> Void
        init(completion: @escaping (Data?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9))
        }
    }
}
