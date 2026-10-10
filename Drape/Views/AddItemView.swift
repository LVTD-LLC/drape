import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ProcessingCoordinator.self) private var processor
    @State private var photos: [Data] = []
    @State private var selection: [PhotosPickerItem] = []
    @State private var camera = false
    @State private var importing = false
    @State private var error: String?
    @State private var confirmDiscard = false
    private let maximumPhotos = 6

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Every angle tells a story.").font(Style.title)
                    Text("Start with the whole piece. Add a few different angles, close-up details, and a label if there is one. Up to six photos help us get to know it.")
                        .foregroundStyle(.secondary)
                    if !photos.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(photos.indices, id: \.self) { index in
                                    VStack(spacing: 8) {
                                        GarmentImage(data: photos[index])
                                            .frame(width: 130, height: 160)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                        Text(index == 0 ? "Whole piece" : "Photo \(index + 1)").font(.caption)
                                        Button("Remove photo \(index + 1)", systemImage: "xmark.circle.fill", role: .destructive) {
                                            photos.remove(at: index)
                                        }.labelStyle(.iconOnly)
                                    }
                                }
                            }
                        }.scrollIndicators(.hidden)
                    }
                    HStack(spacing: 12) {
                        Button { Task { await openCamera() } } label: {
                            Label(photos.isEmpty ? "Camera" : "Take another", systemImage: "camera").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                        PhotosPicker(selection: $selection, maxSelectionCount: max(1, maximumPhotos - photos.count), matching: .images, photoLibrary: .shared()) {
                            Label("Photos", systemImage: "photo").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).controlSize(.large)
                    }.disabled(importing || photos.count >= maximumPhotos)
                    if importing { ProgressView("Preparing photo…") }
                    Label("Lay it flat or hold it in good light. Make the first photo a clear view of the whole piece.", systemImage: "sun.max")
                        .font(.footnote).foregroundStyle(.secondary)
                    Label("Add to wardrobe sends these photos to Drape’s AI providers to fill in the details and create a studio photo. Originals are saved first. You can edit everything afterward.", systemImage: "sparkles")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Add to wardrobe") { save(useAI: true) }
                        .buttonStyle(PrimaryButton()).disabled(photos.isEmpty || importing).accessibilityIdentifier("savePiece")
                    Button("Save photos only") { save(useAI: false) }
                        .font(.footnote).disabled(photos.isEmpty || importing)
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                        Button("Use test photo") { photos.append(DemoData.photo(color: .brown, symbol: "tshirt.fill")) }
                            .disabled(photos.count >= maximumPhotos).accessibilityIdentifier("testPhoto")
                    }
                    #endif
                }.padding(24)
            }.background(Style.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") {
                if photos.isEmpty { dismiss() } else { confirmDiscard = true }
            }.disabled(importing) } }
            .interactiveDismissDisabled(!photos.isEmpty || importing)
            .confirmationDialog("Discard these photos?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard photos", role: .destructive) { dismiss() }
            }
            .sheet(isPresented: $camera) { CameraView { data in
                camera = false
                if let data { prepare(data) }
            }.ignoresSafeArea() }
            .onChange(of: selection) { _, selected in
                guard !selected.isEmpty else { return }
                importing = true
                Task {
                    defer { importing = false; selection = [] }
                    for photo in selected.prefix(maximumPhotos - photos.count) {
                        do {
                            guard let data = try await photo.loadTransferable(type: Data.self) else { throw PhotoError.unreadable }
                            photos.append(try await Task.detached { try ImageTools.normalized(data) }.value)
                        } catch { self.error = error.localizedDescription }
                    }
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
    private func prepare(_ data: Data) {
        importing = true
        Task {
            defer { importing = false }
            do { photos.append(try await Task.detached { try ImageTools.normalized(data) }.value) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func save(useAI: Bool) {
        guard let first = photos.first, !importing else { return }
        importing = true
        Task {
            defer { importing = false }
            let thumbnail = await Task.detached { ImageTools.thumbnail(first) }.value
            let item = Garment(front: first)
            do {
                try item.setExtraPhotos(Array(photos.dropFirst()))
                item.thumbnail = thumbnail
                context.insert(item)
                try context.save()
                processor.start(item, context: context, configuration: useAI ? .automatic : nil)
                dismiss()
            } catch {
                if item.modelContext != nil { context.delete(item) }
                self.error = "Couldn’t save your piece. \(error.localizedDescription)"
            }
        }
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
