import Foundation
import Observation
import SwiftData

@MainActor @Observable final class ProcessingCoordinator {
    private(set) var activeIDs: Set<UUID> = []
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func start(_ item: Garment, context: ModelContext, configuration: AIConfiguration? = nil) {
        guard !activeIDs.contains(item.id) else { return }
        let id = item.id
        activeIDs.insert(id)
        item.processingState = "processing"
        item.processingMessage = configuration == nil ? "Preparing your photo on this iPhone…" : "Preparing your photo and asking AI…"
        do { try context.save() } catch {
            item.processingState = "failed"; item.processingMessage = error.localizedDescription
            activeIDs.remove(id); return
        }
        let front = item.front, back = item.back, label = item.label
        tasks[id] = Task { [weak self] in
            defer { self?.activeIDs.remove(id); self?.tasks[id] = nil }
            let local = await ImageTools.process(front: front, label: label)
            guard !Task.isCancelled, item.modelContext != nil else { return }
            item.cutout = local.cutout ?? item.cutout
            item.labelText = local.labelText
            item.thumbnail = ImageTools.thumbnail(item.displayPhoto)
            var messages: [String] = []
            if local.cutout == nil { messages.append("Background cleanup wasn’t available for this photo. Your original is kept.") }
            if let configuration {
                var photos = [PhotoInput(role: .front, data: front)]
                if let back { photos.append(PhotoInput(role: .back, data: back)) }
                if let label { photos.append(PhotoInput(role: .label, data: label)) }
                do {
                    let suggestions = try await OpenRouter.shared.analyze(photos: photos, configuration: configuration)
                    guard !Task.isCancelled, item.modelContext != nil else { return }
                    item.suggestions = suggestions
                    item.analysisModel = configuration.analysisModel
                    try context.save()
                } catch {
                    guard !Task.isCancelled else { return }
                    messages.append(error.localizedDescription)
                }
                if configuration.generateStudio {
                    item.processingMessage = "Creating your studio photo…"
                    do {
                        let studio = try await OpenRouter.shared.studioPhoto(front: front, configuration: configuration)
                        guard !Task.isCancelled, item.modelContext != nil else { return }
                        item.studio = studio
                        item.imageModel = configuration.imageModel
                        // Generated imagery is opt-in after the user has compared it with the original.
                    } catch {
                        guard !Task.isCancelled else { return }
                        messages.append("Studio photo: " + error.localizedDescription)
                    }
                }
            }
            guard !Task.isCancelled, item.modelContext != nil else { return }
            item.processingState = messages.isEmpty ? "ready" : "attention"
            item.processingMessage = messages.joined(separator: "\n\n")
            do { try context.save() }
            catch { item.processingState = "failed"; item.processingMessage = "Couldn’t save the result: \(error.localizedDescription)" }
        }
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel(); tasks[id] = nil; activeIDs.remove(id)
    }
    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll(); activeIDs.removeAll()
    }
    func recoverInterrupted(in context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<Garment>())
        for item in items where item.processingState == "processing" && !activeIDs.contains(item.id) {
            item.processingState = "attention"
            item.processingMessage = "Processing was interrupted. Your photos are saved. Tap Prepare photo or Ask AI to try again."
        }
        try context.save()
    }
}
