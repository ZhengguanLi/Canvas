import AppKit
import Foundation

/// Launches a directory without interpolating its path into shell code.
enum ProjectLauncher {
    /// Quotes data values; the user's command is interpreted only by the child shell.
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func launchScript(project: Project, configuration: LaunchConfiguration, cleanupDirectory: URL? = nil) throws -> String {
        guard configuration.isValid else { throw LaunchError.invalidConfiguration }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.folderPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LaunchError.missingFolder
        }
        let path = configuration.workingDirectory
        let directory = path.isEmpty ? project.folderURL :
            (path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true) : project.folderURL.appendingPathComponent(path, isDirectory: true))
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LaunchError.missingWorkingDirectory
        }
        let environment = configuration.environment.sorted { $0.key < $1.key }
            .map { shellQuote($0.key + "=" + $0.value) }.joined(separator: " ")
        // Load the user's tool paths first, then apply the explicit project settings.
        let command = "cd -- " + shellQuote(directory.standardizedFileURL.path) + " || exit 1\n" +
            "exec /usr/bin/env " + environment + " /bin/zsh -c " + shellQuote(configuration.command)
        let cleanup = cleanupDirectory.map { "\n/bin/rmdir -- " + shellQuote($0.path) } ?? ""
        return """
        #!/bin/zsh
        /bin/rm -f -- "$0"\(cleanup)
        /bin/zsh -l -c \(shellQuote(command))

        """
    }

    @MainActor
    static func run(_ project: Project, configuration: LaunchConfiguration) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectCanvas-" + UUID().uuidString, isDirectory: true)
        let script = try launchScript(project: project, configuration: configuration, cleanupDirectory: directory)
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            throw LaunchError.appMissing("Terminal")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("Launch.command")
        // The private directory prevents other users reading environment values while Terminal opens.
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            let options = NSWorkspace.OpenConfiguration()
            options.activates = true
            _ = try await NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: options)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

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
        case missingFolder, failed, appMissing(String), command(String), invalidConfiguration, missingWorkingDirectory
        var errorDescription: String? {
            switch self {
            case .invalidConfiguration: L10n.tr("启动配置需要名称、命令和有效的环境变量名称。")
            case .missingWorkingDirectory: L10n.tr("启动工作目录不存在，请检查启动配置。")
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
