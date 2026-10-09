import SwiftUI
import SwiftData
import LocalAuthentication

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(ProcessingCoordinator.self) private var processor
    @AppStorage("aiEnabled") private var aiEnabled = false
    @AppStorage("studioEnabled") private var studioEnabled = false
    @AppStorage("analysisModel") private var analysisModel = "google/gemini-2.5-flash"
    @AppStorage("imageModel") private var imageModel = "google/gemini-2.5-flash-image"
    @AppStorage("lockEnabled") private var lockEnabled = false
    @State private var key = ""
    @State private var keySaved = false
    @State private var models: [ModelOption] = []
    @State private var fetchingModels = false
    @State private var error: String?
    @State private var notice: String?
    @State private var document: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingArchive: WardrobeArchive?
    @State private var confirmImport = false
    @State private var confirmDelete = false
    @State private var working = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Make it yours.").font(.system(.title, design: .serif))
                        Text("A thoughtful home for your wardrobe.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section {
                    SecureField("OpenRouter API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    Button(keySaved ? "Update secure key" : "Save key securely") {
                        do {
                            key = key.trimmingCharacters(in: .whitespacesAndNewlines)
                            try Keychain.save(key)
                            keySaved = !key.isEmpty
                            if !keySaved { aiEnabled = false }
                            notice = keySaved ? "Your key is saved in this iPhone’s Keychain." : "Your OpenRouter key has been removed."
                        } catch { self.error = error.localizedDescription }
                    }
                    if keySaved {
                        Button("Disconnect OpenRouter", role: .destructive) {
                            do { try Keychain.save(""); key = ""; keySaved = false; aiEnabled = false; studioEnabled = false }
                            catch { self.error = error.localizedDescription }
                        }.disabled(!processor.activeIDs.isEmpty)
                    }
                    Toggle("Suggest details when adding", isOn: $aiEnabled).disabled(!keySaved)
                    Toggle("Generate studio photos", isOn: $studioEnabled).disabled(!keySaved)
                } header: { Text("AI assistant") } footer: {
                    Text("AI is optional. You’ll confirm before photos are sent to OpenRouter and its model providers. Requests use your own OpenRouter credits; image generation costs extra. Your key is kept in Keychain and never included in exports.")
                }
                Section {
                    NavigationLink {
                        ModelPicker(title: "Analysis model", options: models.filter(\.supportsAnalysis), selected: $analysisModel)
                    } label: { modelRow("Clothing details", model: analysisModel) }
                    NavigationLink {
                        ModelPicker(title: "Image model", options: models.filter(\.supportsImage), selected: $imageModel)
                    } label: { modelRow("Studio photography", model: imageModel) }
                    Button { Task { await loadModels() } } label: {
                        HStack { Text("Refresh available models"); if fetchingModels { Spacer(); ProgressView() } }
                    }.disabled(fetchingModels)
                } header: { Text("Choose your models") } footer: {
                    Text("Analysis models must support images and structured responses. Image models must support image input and output. Availability and pricing depend on the provider.")
                }
                Section {
                    Toggle("Require Face ID or passcode", isOn: Binding(get: { lockEnabled }, set: { enabled in
                        Task { await changeLock(enabled) }
                    }))
                    NavigationLink("Privacy & your photos") { PrivacyView() }
                } header: { Text("Your privacy") } footer: {
                    Text("Your wardrobe is stored on this iPhone. It may be included in your device backup, depending on your iCloud settings. Cross-device sync isn’t enabled yet.")
                }
                Section {
                    Button("Export wardrobe", systemImage: "square.and.arrow.up") { export() }
                    Button("Restore a backup", systemImage: "square.and.arrow.down") { importing = true }
                    if working { ProgressView("Preparing your wardrobe…") }
                } header: { Text("Keep a copy") } footer: {
                    Text("Export includes your clothing photos, details, and looks. Keep this file private. Restore adds missing pieces without replacing existing ones. Backups up to 100 MB are supported.")
                }.disabled(working || !processor.activeIDs.isEmpty)
                Section {
                    Button("Delete all wardrobe data", role: .destructive) { confirmDelete = true }.disabled(working || !processor.activeIDs.isEmpty)
                } footer: { Text("Drape 1.0 · Made for the clothes you love.") }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .task {
                do { key = try Keychain.read(); keySaved = !key.isEmpty } catch { self.error = error.localizedDescription }
                if models.isEmpty { await loadModels() }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Drape wardrobe") { result in
                if case .failure(let failure) = result { error = failure.localizedDescription }
                document = nil
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { readArchive(url) }
                else if case .failure(let failure) = result { error = failure.localizedDescription }
            }
            .confirmationDialog("Restore this wardrobe?", isPresented: $confirmImport, titleVisibility: .visible) {
                Button("Add missing pieces") {
                    guard let archive = pendingArchive else { return }
                    do { let count = try archive.restore(into: context); notice = "Restored \(count) new pieces. Existing pieces were kept." }
                    catch { self.error = error.localizedDescription }
                    pendingArchive = nil
                }
                Button("Cancel", role: .cancel) { pendingArchive = nil }
            } message: { Text("This backup contains \(pendingArchive?.items.count ?? 0) pieces and \(pendingArchive?.looks.count ?? 0) looks.") }
            .confirmationDialog("Delete your entire wardrobe?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { deleteAll() }
            } message: { Text("All pieces, photos, and looks on this iPhone will be permanently removed. Export a backup first if you want to keep them. Your OpenRouter key will also be removed.") }
            .alert("Drape", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) { notice = nil }
            } message: { Text(notice ?? "") }
            .errorNotice($error)
        }
    }
    private func modelRow(_ title: String, model: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title); Text(model).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
    }
    private func loadModels() async {
        fetchingModels = true
        defer { fetchingModels = false }
        do { models = try await OpenRouter.shared.models() }
        catch { self.error = "Couldn’t refresh models. Your saved choices still work. \(error.localizedDescription)" }
    }
    private func changeLock(_ enabled: Bool) async {
        do {
            if try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: enabled ? "Protect your wardrobe" : "Turn off wardrobe protection") {
                lockEnabled = enabled
            }
        } catch { self.error = "You’ll need a device passcode or Face ID to change this setting." }
    }
    private func export() {
        do {
            let archive = try WardrobeArchive.make(context: context)
            let data = try JSONEncoder().encode(archive)
            guard data.count <= 100_000_000 else { throw BackupError.tooLarge }
            document = BackupDocument(data: data); exporting = true
        } catch { self.error = error.localizedDescription }
    }
    private func readArchive(_ url: URL) {
        working = true
        Task {
            defer { working = false }
            do {
                let archive = try await Task.detached {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 100_000_000 else { throw BackupError.tooLarge }
                    return try WardrobeArchive.decode(Data(contentsOf: url))
                }.value
                pendingArchive = archive; confirmImport = true
            } catch { self.error = error.localizedDescription }
        }
    }
    private func deleteAll() {
        do {
            try Keychain.save("")
            key = ""; keySaved = false; aiEnabled = false; studioEnabled = false
            for look in try context.fetch(FetchDescriptor<Look>()) { context.delete(look) }
            for item in try context.fetch(FetchDescriptor<Garment>()) { context.delete(item) }
            try context.save()
            key = ""; keySaved = false; aiEnabled = false; studioEnabled = false
            notice = "Your wardrobe and OpenRouter key have been deleted."
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct ModelPicker: View {
    let title: String
    let options: [ModelOption]
    @Binding var selected: String
    @State private var search = ""
    var body: some View {
        List {
            Section("Selected model") { Text(selected).font(.footnote).textSelection(.enabled) }
            Section("Available models") {
                if options.isEmpty { Text("Return to Settings and refresh available models.").foregroundStyle(.secondary) }
                ForEach(options.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }) { model in
                    Button { selected = model.id } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) { Text(model.name).foregroundStyle(.primary); Text(model.id).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if selected == model.id { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                        }
                    }
                }
            }
            Section("Custom model ID") {
                TextField("provider/model-id", text: $selected).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }.navigationTitle(title).searchable(text: $search, prompt: "Find a model")
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("On your iPhone") {
                Text("Drape stores clothing photos, details, and looks in its private app storage. Background removal and label text recognition run on the device. There is no Drape account or cross-device sync in this version.")
                Text("Photos are resized and re-encoded before saving, removing location metadata. Your OpenRouter key is stored in this device’s Keychain and is excluded from exports.")
            }
            Section("When you ask AI") {
                Text("After you confirm, selected clothing photos are sent over HTTPS to OpenRouter and the model providers you choose. They may process or retain requests under their own policies. Drape does not send your name, Apple account, or location. We request providers that disallow data collection for clothing analysis; image generation is subject to the selected provider’s policy.")
                Link("OpenRouter privacy policy", destination: URL(string: "https://openrouter.ai/privacy")!)
                Text("AI can be wrong. Size, materials, and care should be checked against your label. Generated photos may change details; compare them with your original before using them.")
            }
            Section("You’re in control") {
                Text("You can use Drape without AI, remove the API key, export a copy of your wardrobe, or delete all local data in Settings. Deleting Drape removes its local wardrobe. Files you exported and requests already sent to providers are not deleted by removing local data.")
                Text("Drape has no advertising or analytics SDKs. Backups saved to Files may sync through your chosen cloud provider. The optional lock uses Apple’s device authentication; Drape never receives your Face ID data.")
            }
        }.navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
    }
}
