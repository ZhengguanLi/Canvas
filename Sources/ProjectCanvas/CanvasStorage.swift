import Foundation

/// Keeps damaged source data untouched until the user explicitly restores a validated backup.
final class CanvasStorage {
    enum StorageError: LocalizedError {
        case unsupportedVersion, invalidReferences, recoveryRequired, noBackup
        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: L10n.tr("画布数据版本不受支持。原文件已保留。")
            case .invalidReferences: L10n.tr("画布数据包含重复标识或无效引用。原文件已保留。")
            case .recoveryRequired: L10n.tr("原数据无法读取，已暂停保存。请从备份恢复。")
            case .noBackup: L10n.tr("没有可用的有效备份。")
            }
        }
    }

    let url: URL
    private(set) var requiresRecovery = false
    init(url: URL) { self.url = url }
    private func backupURL(_ index: Int) -> URL { url.appendingPathExtension("backup\(index)") }

    static func decode(_ bytes: Data) throws -> ProjectCanvasData {
        let data = try JSONDecoder().decode(ProjectCanvasData.self, from: bytes)
        let projectIDs = Set(data.projects.map(\.id))
        guard projectIDs.count == data.projects.count,
              Set(data.groups.map(\.id)).count == data.groups.count else { throw StorageError.invalidReferences }
        guard data.projects.allSatisfy({ project in
            let links = project.links ?? []
            return links.allSatisfy { $0.validatedURL != nil } && Set(links.map(\.id)).count == links.count
        }) else { throw StorageError.invalidReferences }
        for group in data.groups {
            let cards = Set(group.cards.map(\.id))
            guard cards.count == group.cards.count,
                  Set(group.connections.map(\.id)).count == group.connections.count,
                  group.cards.allSatisfy({ projectIDs.contains($0.projectID) && $0.x.isFinite && $0.y.isFinite }),
                  group.connections.allSatisfy({ cards.contains($0.fromCardID) && cards.contains($0.toCardID) }) else { throw StorageError.invalidReferences }
            guard Set(group.regions.map(\.id)).count == group.regions.count,
                  group.regions.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.cardIDs.isEmpty && cards.isSuperset(of: $0.cardIDs) }) else { throw StorageError.invalidReferences }
            if let viewport = group.viewport {
                guard viewport.zoom.isFinite && viewport.zoom > 0 && viewport.offsetX.isFinite && viewport.offsetY.isFinite else { throw StorageError.invalidReferences }
            }
        }
        return data
    }

    func load() throws -> ProjectCanvasData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try Self.decode(Data(contentsOf: url)) }
        catch { requiresRecovery = true; throw error }
    }

    func save(_ data: ProjectCanvasData, rotatingBackup: Bool = true) throws {
        guard !requiresRecovery else { throw StorageError.recoveryRequired }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(data)
        _ = try Self.decode(encoded)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let old: Data
            do { old = try Data(contentsOf: url); _ = try Self.decode(old) }
            catch { requiresRecovery = true; throw error }
            // Do not rotate identical saves (selection/view updates often repeat).
            if old == encoded { return }
            if rotatingBackup {
                for index in stride(from: 4, through: 1, by: -1) {
                    if let bytes = try? Data(contentsOf: backupURL(index)), (try? Self.decode(bytes)) != nil {
                        try bytes.write(to: backupURL(index + 1), options: .atomic)
                    }
                }
                try old.write(to: backupURL(1), options: .atomic)
            }
        }
        try encoded.write(to: url, options: .atomic)
    }

    func replacePreservingOriginal(_ data: ProjectCanvasData) throws {
        let bytes = try JSONEncoder().encode(data)
        _ = try Self.decode(bytes)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.copyItem(at: url, to: url.appendingPathExtension("preserved-\(UUID().uuidString)"))
        }
        try bytes.write(to: url, options: .atomic)
        requiresRecovery = false
    }

    func restoreBackup() throws -> ProjectCanvasData {
        for index in 1...5 {
            guard let bytes = try? Data(contentsOf: backupURL(index)), let data = try? Self.decode(bytes) else { continue }
            if FileManager.default.fileExists(atPath: url.path) {
                let preserved = url.appendingPathExtension("preserved-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: url, to: preserved)
            }
            try bytes.write(to: url, options: .atomic)
            requiresRecovery = false
            return data
        }
        throw StorageError.noBackup
    }
}
