import Foundation

enum DesktopDisplayMode: String, CaseIterable, Identifiable {
    case desktopBackground
    case foregroundOverlay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktopBackground: L10n.tr("桌面背景层（位于普通窗口后面）")
        case .foregroundOverlay: L10n.tr("当前桌面前置覆盖")
        }
    }
}

struct Project: Identifiable, Codable, Equatable {
    var id: UUID
    var editor: EditorChoice?
    var openInNewWindow: Bool?
    var notes: String?
    var links: [ProjectLink]?
    private var storedTags: [String]?
    var tags: [String] {
        get { storedTags ?? [] }
        set { storedTags = newValue }
    }
    private var storedLaunchConfigurations: [LaunchConfiguration]?
    var launchConfigurations: [LaunchConfiguration] {
        get { storedLaunchConfigurations ?? [] }
        set { storedLaunchConfigurations = newValue }
    }
    var lastOpenedAt: Date?
    private var storedOpenCount: Int?
    var openCount: Int {
        get { storedOpenCount ?? 0 }
        set { storedOpenCount = newValue }
    }
    var folderPath: String

    var folderURL: URL { URL(fileURLWithPath: folderPath, isDirectory: true) }
    var folderName: String { folderURL.lastPathComponent }

    init(id: UUID = UUID(), folderURL: URL) {
        self.id = id
        self.folderPath = folderURL.standardizedFileURL.path
    }
}

struct LaunchConfiguration: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var command: String
    /// Empty or relative paths resolve against the project folder.
    var workingDirectory = ""
    var environment: [String: String] = [:]

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !command.contains("\0") && !workingDirectory.contains("\0") &&
        environment.allSatisfy { key, value in
            key.range(of: #"\A[A-Za-z_][A-Za-z0-9_]*\z"#, options: .regularExpression) != nil && !value.contains("\0")
        }
    }
}

struct ProjectCard: Identifiable, Codable, Equatable {
    var id: UUID
    var projectID: UUID?
    var clipboard: CanvasClipboardContent?
    var x: Double
    var y: Double
    var customName: String?
    private var cardColor: CardColor?
    var color: CardColor {
        get { cardColor ?? .neutral }
        set { cardColor = newValue }
    }

    init(id: UUID = UUID(), projectID: UUID, x: Double, y: Double, customName: String? = nil) {
        self.id = id
        self.projectID = projectID
        self.x = x
        self.y = y
        self.customName = customName
    }

    init(id: UUID = UUID(), clipboard: CanvasClipboardContent, x: Double, y: Double) {
        self.id = id
        self.clipboard = clipboard
        self.x = x
        self.y = y
    }

}

struct ProjectConnection: Identifiable, Codable, Equatable {
    var id: UUID
    var fromCardID: UUID
    var toCardID: UUID
    private var connectionKind: ConnectionKind?
    var label: String?
    var kind: ConnectionKind {
        get { connectionKind ?? .dependency }
        set { connectionKind = newValue }
    }

    init(id: UUID = UUID(), fromCardID: UUID, toCardID: UUID) {
        self.id = id
        self.fromCardID = fromCardID
        self.toCardID = toCardID
    }
}

struct ProjectGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var cards: [ProjectCard]
    var connections: [ProjectConnection]
    var viewport: CanvasViewport?
    /// Tracks canvas rebasing so desktop transforms also survive undo and redo.
    var coordinateOffset: CGPoint?
    private var storedRegions: [ProjectRegion]?
    var regions: [ProjectRegion] {
        get { storedRegions ?? [] }
        set { storedRegions = newValue }
    }
    var showsConnections: Bool

    init(id: UUID = UUID(), name: String, cards: [ProjectCard] = [], connections: [ProjectConnection] = [], showsConnections: Bool = false) {
        self.id = id
        self.name = name
        self.cards = cards
        self.connections = connections
        self.showsConnections = showsConnections
    }
}

struct ProjectCanvasData: Codable, Equatable {
    var schemaVersion: Int = 1
    var projects: [Project]
    var groups: [ProjectGroup]
    var selectedGroupID: UUID?
    var defaultEditor: EditorChoice? = nil
    var defaultOpenInNewWindow: Bool? = nil

    init(projects: [Project], groups: [ProjectGroup], selectedGroupID: UUID?) {
        self.projects = projects
        self.groups = groups
        self.selectedGroupID = selectedGroupID
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, projects, groups, selectedGroupID, defaultEditor, defaultOpenInNewWindow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion == 1 else { throw CanvasStorage.StorageError.unsupportedVersion }
        projects = try c.decode([Project].self, forKey: .projects)
        groups = try c.decode([ProjectGroup].self, forKey: .groups)
        selectedGroupID = try c.decodeIfPresent(UUID.self, forKey: .selectedGroupID)
        defaultEditor = try c.decodeIfPresent(EditorChoice.self, forKey: .defaultEditor)
        defaultOpenInNewWindow = try c.decodeIfPresent(Bool.self, forKey: .defaultOpenInNewWindow)
    }

    static var empty: ProjectCanvasData { ProjectCanvasData(projects: [], groups: [ProjectGroup(name: L10n.tr("我的项目"))], selectedGroupID: nil) }
}

enum CardColor: String, CaseIterable, Identifiable, Codable {
    case neutral, blue, green, orange, pink, purple
    var id: String { rawValue }
    var title: String {
        switch self {
        case .neutral: L10n.tr("默认")
        case .blue: L10n.tr("蓝色")
        case .green: L10n.tr("绿色")
        case .orange: L10n.tr("橙色")
        case .pink: L10n.tr("粉色")
        case .purple: L10n.tr("紫色")
        }
    }
}

enum EditorChoice: String, CaseIterable, Identifiable, Codable {
    case vscode, cursor, intellij, finder, terminal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vscode: "VS Code"
        case .cursor: "Cursor"
        case .intellij: "IntelliJ IDEA"
        case .finder: "Finder"
        case .terminal: "Terminal"
        }
    }
}

enum ConnectionKind: String, CaseIterable, Identifiable, Codable {
    case dependency, call, configuration, related
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dependency: L10n.tr("依赖")
        case .call: L10n.tr("调用")
        case .configuration: L10n.tr("配置")
        case .related: L10n.tr("关联")
        }
    }
}

struct CanvasViewport: Codable, Equatable {
    var zoom: Double = 1
    var offsetX: Double = 0
    var offsetY: Double = 0
}

extension ProjectGroup {
    /// Traverses directed edges, excluding the starting cards even in cycles.
    func relatedCardIDs(to seeds: Set<UUID>, upstream: Bool) -> Set<UUID> {
        var visited = seeds
        var pending = Array(seeds)
        while let card = pending.popLast() {
            for edge in connections {
                let source = upstream ? edge.toCardID : edge.fromCardID
                let destination = upstream ? edge.fromCardID : edge.toCardID
                if source == card && visited.insert(destination).inserted { pending.append(destination) }
            }
        }
        return visited.subtracting(seeds)
    }
}

struct ProjectLink: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var address: String
    var validatedURL: URL? {
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return url
    }
}

struct ProjectRegion: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var color: CardColor
    var cardIDs: Set<UUID>
}

struct ProjectSearchResult: Identifiable {
    var id: String { "\(groupID.uuidString)/\(card.id.uuidString)" }
    let groupID: UUID
    let groupName: String
    let card: ProjectCard
    let project: Project
}

struct CanvasLocateRequest: Equatable {
    var id = UUID()
    let groupID: UUID
    let cardID: UUID
}
