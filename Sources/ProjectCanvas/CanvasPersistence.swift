import Foundation

/// All storage access after initial load is serialized, including recovery barriers.
final class CanvasPersistence: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ProjectCanvas.persistence", qos: .utility)
    private let storage: CanvasStorage
    private var pending: ProjectCanvasData?
    private var generation = 0
    private var failureID: UUID?
    private var failureHandler: (@Sendable (Error, Bool, UUID) -> Void)?
    var onFailure: (@Sendable (Error, Bool, UUID) -> Void)? {
        get { queue.sync { failureHandler } }
        set { queue.sync { failureHandler = newValue } }
    }

    init(storage: CanvasStorage) { self.storage = storage }

    func save(_ snapshot: ProjectCanvasData, rotatingBackup: Bool) {
        queue.async {
            self.generation += 1
            self.pending = nil
            self.write(snapshot, rotatingBackup: rotatingBackup)
        }
    }

    func scheduleViewport(_ snapshot: ProjectCanvasData) {
        queue.async {
            self.pending = snapshot
            self.generation += 1
            let generation = self.generation
            self.queue.asyncAfter(deadline: .now() + 0.3) {
                guard self.generation == generation else { return }
                self.flushPending()
            }
        }
    }

    private func write(_ snapshot: ProjectCanvasData, rotatingBackup: Bool) {
        do {
            try storage.save(snapshot, rotatingBackup: rotatingBackup)
            failureID = nil
        } catch {
            let id = UUID()
            failureID = id
            failureHandler?(error, storage.requiresRecovery, id)
        }
    }

    private func flushPending() {
        guard let snapshot = pending else { return }
        pending = nil
        generation += 1
        write(snapshot, rotatingBackup: false)
    }

    func flush() { queue.sync { flushPending() } }

    func isCurrentFailure(_ id: UUID) -> Bool { queue.sync { failureID == id } }

    func restoreBackup() throws -> ProjectCanvasData {
        try queue.sync {
            // Discard queued viewport changes before replacing the document.
            pending = nil
            generation += 1
            let restored = try storage.restoreBackup()
            failureID = nil
            return restored
        }
    }

    func replacePreservingOriginal(_ snapshot: ProjectCanvasData) throws {
        try queue.sync {
            pending = nil
            generation += 1
            try storage.replacePreservingOriginal(snapshot)
            failureID = nil
        }
    }
}
