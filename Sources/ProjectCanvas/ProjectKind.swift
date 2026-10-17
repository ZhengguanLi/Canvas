import Foundation

/// A coarse project type inferred from marker files, used only for the card icon.
enum ProjectKind: String, CaseIterable, Sendable {
    case swift, xcode, node, python, rust, go, java, ruby, web, folder

    var symbol: String {
        switch self {
        case .swift: "swift"
        case .xcode: "hammer"
        case .node: "shippingbox"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .rust: "gearshape.2"
        case .go: "bolt"
        case .java: "cup.and.saucer"
        case .ruby: "diamond"
        case .web: "globe"
        case .folder: "folder"
        }
    }

    /// First match wins, so more specific markers come first.
    private static let markers: [(ProjectKind, [String])] = [
        (.swift, ["Package.swift"]),
        (.rust, ["Cargo.toml"]),
        (.go, ["go.mod"]),
        (.node, ["package.json"]),
        (.python, ["pyproject.toml", "setup.py", "requirements.txt", "Pipfile"]),
        (.java, ["pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle"]),
        (.ruby, ["Gemfile"]),
        (.web, ["index.html"]),
    ]

    static func detect(at directory: URL, fileManager: FileManager = .default) -> ProjectKind {
        for (kind, files) in markers where files.contains(where: { fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) }) {
            return kind
        }
        let entries = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return entries.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") } ? .xcode : .folder
    }
}
