import AppKit
import Foundation

/// Launches a directory without interpolating its path into shell code.
enum ProjectLauncher {
    static func arguments(editor: EditorChoice, newWindow: Bool, path: String) -> [String] {
        switch editor {
        case .vscode, .cursor: return [newWindow ? "--new-window" : "--reuse-window", path]
        default: return [path]
        }
    }

    @MainActor
    static func open(_ project: Project, editor: EditorChoice, newWindow: Bool) async throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.folderPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LaunchError.missingFolder
        }
        if editor == .finder {
            guard NSWorkspace.shared.open(project.folderURL) else { throw LaunchError.failed }
            return
        }
        let identifiers: [String]
        switch editor {
        case .vscode: identifiers = ["com.microsoft.VSCode"]
        case .cursor: identifiers = ["com.todesktop.230313mzl4w4u92"]
        case .intellij: identifiers = ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"]
        case .terminal: identifiers = ["com.apple.Terminal"]
        case .finder: identifiers = []
        }
        let application = identifiers.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
        if editor == .vscode || editor == .cursor {
            let command = editor == .vscode ? "code" : "cursor"
            var candidates = application.map { [$0.appendingPathComponent("Contents/Resources/app/bin/\(command)")] } ?? []
            let directories = ["/opt/homebrew/bin", "/usr/local/bin"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            candidates += directories.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).appendingPathComponent(command) }
            guard let cli = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
                throw LaunchError.appMissing(editor.title)
            }
            let args = arguments(editor: editor, newWindow: newWindow, path: project.folderPath)
            let result = try await Task.detached(priority: .userInitiated) {
                try ProcessRunner.run(executable: cli.path, arguments: args)
            }.value
            guard result.status == 0 else { throw LaunchError.command(result.output) }
        } else {
            guard let application else { throw LaunchError.appMissing(editor.title) }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try await NSWorkspace.shared.open([project.folderURL], withApplicationAt: application, configuration: config)
        }
    }

    enum LaunchError: LocalizedError {
        case missingFolder, failed, appMissing(String), command(String)
        var errorDescription: String? {
            switch self {
            case .missingFolder: L10n.tr("文件夹不存在，请右键卡片选择“重新定位文件夹”。")
            case .failed: L10n.tr("无法打开文件夹。")
            case .appMissing(let app): L10n.format("找不到 %@，请安装应用或更改打开方式。", app)
            case .command(let output): L10n.format("编辑器启动失败：%@", String(output.prefix(500)))
            }
        }
    }
}

/// Drains stdout while the child runs so verbose commands cannot block on a full pipe.
enum ProcessRunner {
    static func run(executable: String, arguments: [String], directory: URL? = nil) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: bytes, as: UTF8.self))
    }
}
