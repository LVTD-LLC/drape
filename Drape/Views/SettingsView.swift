import SwiftUI
import SwiftData
import LocalAuthentication

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(ProcessingCoordinator.self) private var processor
    @AppStorage("lockEnabled") private var lockEnabled = false
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
            } message: { Text("All pieces, photos, and looks on this iPhone will be permanently removed. Export a backup first if you want to keep them.") }
            .alert("Drape", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) { notice = nil }
            } message: { Text(notice ?? "") }
            .errorNotice($error)
        }
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
            for look in try context.fetch(FetchDescriptor<Look>()) { context.delete(look) }
            for item in try context.fetch(FetchDescriptor<Garment>()) { context.delete(item) }
            try context.save()
            notice = "Your wardrobe has been deleted."
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("On your iPhone") {
                Text("Drape stores clothing photos, details, and looks in its private app storage. Background removal and label text recognition run on the device. There is no Drape account or cross-device sync in this version.")
                Text("Photos are resized and re-encoded before saving, removing location metadata.")
            }
            Section("When you add a piece") {
                Text("When you tap Add to wardrobe or Finish preparing, selected clothing photos are sent through Drape’s AI service to OpenRouter and its model providers. They may process or retain requests under their own policies. Drape does not send your name, Apple account, or location. We request providers that disallow data collection for clothing analysis; image generation is subject to the selected provider’s policy.")
                Link("OpenRouter privacy policy", destination: URL(string: "https://openrouter.ai/privacy")!)
                Text("AI can be wrong. Size, materials, and care should be checked against your label. Generated photos may change details; compare them with your original before using them.")
            }
            Section("You’re in control") {
                Text("Choose Save photos only to use Drape without AI, export a copy of your wardrobe, or delete all local data in Settings. Deleting Drape removes its local wardrobe. Files you exported and requests already sent to providers are not deleted by removing local data.")
                Text("Drape has no advertising or analytics SDKs. Backups saved to Files may sync through your chosen cloud provider. The optional lock uses Apple’s device authentication; Drape never receives your Face ID data.")
            }
        }.navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
    }
}
