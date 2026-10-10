import SwiftUI
import SwiftData
import LocalAuthentication

@main struct DrapeApp: App {
    private let container: ModelContainer?
    private let startupError: String?
    @State private var processor = ProcessingCoordinator()
    init() {
        AIModelDefaults.migrateSavedChoices()
        do {
            let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
            let configuration = ModelConfiguration(isStoredInMemoryOnly: testing)
            container = try ModelContainer(for: Garment.self, Look.self, migrationPlan: WardrobeMigrationPlan.self, configurations: configuration)
            startupError = nil
        } catch {
            container = nil; startupError = error.localizedDescription
        }
    }
    var body: some Scene {
        WindowGroup {
            if let container {
                RootView().modelContainer(container).environment(processor).tint(Style.accent)
            } else {
                ContentUnavailableView("Your wardrobe couldn’t open", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Your saved data has not been removed. Restart Drape and try again.\n\n" + (startupError ?? "")))
            }
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ProcessingCoordinator.self) private var processor
    @AppStorage("welcomeCompleted") private var welcomeCompleted = false
    @AppStorage("lockEnabled") private var lockEnabled = false
    @State private var unlocked = false
    @State private var unlocking = false
    @State private var error: String?
    private var testing: Bool { ProcessInfo.processInfo.arguments.contains("--uitesting") }

    var body: some View {
        ZStack {
            if !welcomeCompleted && !testing {
                WelcomeView()
            } else if lockEnabled && !unlocked {
                VStack(spacing: 24) {
                    Image(systemName: "lock").font(.system(size: 40)).foregroundStyle(Style.accent)
                    Text("Just for you.").font(Style.title)
                    Button("Unlock wardrobe", action: unlock).buttonStyle(PrimaryButton()).disabled(unlocking)
                    if let error { Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(Style.canvas)
            } else {
                TabView {
                    WardrobeView()
                        .tabItem { Label("Wardrobe", systemImage: "square.grid.2x2") }
                    LooksView()
                        .tabItem { Label("Looks", systemImage: "rectangle.on.rectangle.angled") }
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                }
            }
            if scenePhase != .active && lockEnabled {
                Style.canvas.ignoresSafeArea().overlay {
                    Text("drape").font(.system(size: 56, weight: .regular, design: .serif)).foregroundStyle(Style.accent)
                }
            }
        }
        .task {
            do { try processor.recoverInterrupted(in: context) } catch { self.error = error.localizedDescription }
            if testing && ProcessInfo.processInfo.arguments.contains("--seed") { try? DemoData.seed(context) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { unlocked = false }
        }
        .onChange(of: lockEnabled) { _, enabled in if enabled { unlocked = true } }
    }
    private func unlock() {
        guard !unlocking else { return }
        unlocking = true; error = nil
        Task { @MainActor in
            defer { unlocking = false }
            do {
                unlocked = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open your private wardrobe")
            } catch { self.error = "Couldn’t unlock. Try again using Face ID or your device passcode." }
        }
    }
}

struct WelcomeView: View {
    @AppStorage("welcomeCompleted") private var welcomeCompleted = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Image(systemName: "tshirt").font(.system(size: 70, weight: .ultraLight)).foregroundStyle(Style.accent)
                .padding(32).background(Style.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 36))
            Text("drape").font(.system(size: 76, weight: .regular, design: .serif)).tracking(-4)
            Text("A little more love for\nwhat you already own.").font(.system(.title2, design: .serif)).fixedSize(horizontal: false, vertical: true)
            Text("Photograph your pieces. Find them at a glance. Bring your next look together.")
                .foregroundStyle(.secondary).font(.body)
            Spacer()
            Label("Your wardrobe starts on this iPhone.", systemImage: "lock.shield").font(.footnote).foregroundStyle(.secondary)
            Button("Create my wardrobe") { welcomeCompleted = true }.buttonStyle(PrimaryButton()).accessibilityIdentifier("welcomeContinue")
                }.frame(maxWidth: .infinity, minHeight: geometry.size.height - 60, alignment: .leading).padding(30)
            }.background(Style.canvas)
        }
    }
}
