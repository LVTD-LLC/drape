import Foundation
import Observation
import SwiftData

@MainActor @Observable final class ProcessingCoordinator {
    private(set) var activeIDs: Set<UUID> = []
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let service: any WardrobeAI
    private let prepare: @Sendable (Data, Data?) async -> LocalPhotoResult

    init(service: any WardrobeAI = OpenRouter.shared,
         prepare: @escaping @Sendable (Data, Data?) async -> LocalPhotoResult = { await ImageTools.process(front: $0, label: $1) }) {
        self.service = service
        self.prepare = prepare
    }

    func start(_ item: Garment, context: ModelContext, configuration: AIConfiguration? = nil) {
        guard !activeIDs.contains(item.id) else { return }
        // Completed stages cannot be repeated, even when optional metadata is missing.
        if configuration != nil && !item.needsAI { return }
        let id = item.id
        activeIDs.insert(id)
        item.processingState = "processing"
        item.processingMessage = "Preparing your piece…"
        do { try context.save() } catch {
            item.processingState = "failed"; item.processingMessage = "Couldn’t save your piece. Your photos are still here."
            activeIDs.remove(id); return
        }
        let front = item.front, label = item.label, photos = item.sourcePhotos
        let initialDetails = item.details
        let initialAttributes = item.attributes
        let service = service, prepare = prepare
        tasks[id] = Task { [weak self] in
            defer { self?.activeIDs.remove(id); self?.tasks[id] = nil }
            let local = await prepare(front, label)
            guard !Task.isCancelled, item.modelContext != nil else { return }
            item.cutout = local.cutout ?? item.cutout
            item.labelText = local.labelText
            let localPhoto = item.displayPhoto
            let localThumbnail = await Task.detached { ImageTools.thumbnail(localPhoto) }.value
            guard !Task.isCancelled, item.modelContext != nil else { return }
            item.thumbnail = localThumbnail
            var messages: [String] = []
            if let configuration {
                if item.analysisModel == nil {
                    do {
                        let analysis = try await service.analyze(photos: photos.map { PhotoInput(data: $0) }, configuration: configuration)
                        guard !Task.isCancelled, item.modelContext != nil else { return }
                        item.details.fillMissing(from: analysis.details, unchangedSince: initialDetails)
                        var generated = analysis.attributes
                        if item.details.category != analysis.details.category ||
                            (item.details.subcategory != initialDetails.subcategory && item.details.subcategory != analysis.details.subcategory) {
                            generated.typeDetail = ""
                        }
                        var attributes = item.attributes
                        attributes.fillMissing(from: generated, unchangedSince: initialAttributes)
                        try item.setAttributes(attributes)
                        item.suggestions = nil
                        item.analysisModel = configuration.analysisModel
                        try context.save()
                    } catch {
                        guard !Task.isCancelled, item.modelContext != nil else { return }
                        messages.append("Details: " + error.localizedDescription)
                    }
                }
                if configuration.generateStudio && item.studio == nil {
                    item.processingMessage = "Creating your studio photo…"
                    do {
                        let studio = try await service.studioPhoto(front: front, configuration: configuration)
                        guard !Task.isCancelled, item.modelContext != nil else { return }
                        item.studio = studio
                        item.useStudio = true
                        item.imageModel = configuration.imageModel
                    } catch {
                        guard !Task.isCancelled, item.modelContext != nil else { return }
                        messages.append("Studio photo: " + error.localizedDescription)
                    }
                }
            }
            guard !Task.isCancelled, item.modelContext != nil else { return }
            let displayPhoto = item.displayPhoto
            let thumbnail = await Task.detached { ImageTools.thumbnail(displayPhoto) }.value
            guard !Task.isCancelled, item.modelContext != nil else { return }
            item.thumbnail = thumbnail
            item.processingState = messages.isEmpty ? "ready" : "attention"
            item.processingMessage = messages.joined(separator: "\n\n")
            do { try context.save() }
            catch { item.processingState = "failed"; item.processingMessage = "Couldn’t save the result. Your original photos are kept." }
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
        for item in items {
            if item.processingState == "processing" && !activeIDs.contains(item.id) {
                item.processingState = "attention"
                item.processingMessage = "Preparation was interrupted. Your photos are saved. You can finish preparing this piece when you’re ready."
            }
            // Existing pending suggestions can fill blanks, but never replace saved edits.
            if let suggestions = item.suggestions {
                item.details.fillMissing(from: suggestions, unchangedSince: item.details)
                item.suggestions = nil
            }
        }
        try context.save()
    }
}

extension ItemDetails {
    mutating func applyEdits(_ edited: Self, comparedTo baseline: Self) {
        for key in [\Self.name, \.color, \.brand, \.size, \.material, \.pattern, \.season, \.care, \.notes] {
            if edited[keyPath: key] != baseline[keyPath: key] { self[keyPath: key] = edited[keyPath: key] }
        }
        if edited.category != baseline.category { category = edited.category; subcategory = edited.subcategory }
        else if edited.subcategory != baseline.subcategory { subcategory = edited.subcategory }
    }

    mutating func fillMissing(from generated: Self, unchangedSince initial: Self) {
        for key in [\Self.name, \.color, \.brand, \.size, \.material, \.pattern, \.season, \.care, \.notes] {
            if self[keyPath: key] == initial[keyPath: key] && initial[keyPath: key].isEmpty {
                self[keyPath: key] = generated[keyPath: key]
            }
        }
        if category == initial.category && initial.category == .other { category = generated.category }
        if category == generated.category && subcategory == initial.subcategory && initial.subcategory.isEmpty {
            subcategory = generated.subcategory
        }
    }
}
