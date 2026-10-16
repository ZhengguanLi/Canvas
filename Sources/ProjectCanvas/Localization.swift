import Combine
import Foundation

/// The user's language preference; system resolves to a supported language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: L10n.tr("跟随系统")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    static func resolve(preferredLanguages: [String]) -> AppLanguage {
        for language in preferredLanguages {
            if language.lowercased().hasPrefix("zh") { return .simplifiedChinese }
            if language.lowercased().hasPrefix("en") { return .english }
        }
        return .english
    }
}

extension Notification.Name {
    static let projectCanvasLanguageChanged = Notification.Name("ProjectCanvasLanguageChanged")
}

/// Observed by the app root without replacing view identity or discarding editor drafts.
final class LanguageController: ObservableObject {
    static let preferenceKey = "applicationLanguage"
    static let shared = LanguageController()
    private let preferences: UserDefaults
    private let preferredLanguages: () -> [String]
    @Published var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            preferences.set(selection.rawValue, forKey: Self.preferenceKey)
            NotificationCenter.default.post(name: .projectCanvasLanguageChanged, object: self)
        }
    }

    init(preferences: UserDefaults = .standard, preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }) {
        self.preferences = preferences
        self.preferredLanguages = preferredLanguages
        selection = AppLanguage(rawValue: preferences.string(forKey: Self.preferenceKey) ?? "") ?? .system
    }

    var resolvedLanguage: AppLanguage {
        selection == .system ? AppLanguage.resolve(preferredLanguages: preferredLanguages()) : selection
    }
    var locale: Locale { Locale(identifier: resolvedLanguage.rawValue) }
}

/// Only application-owned copy is passed here. Stored names, notes and labels remain literal.
enum L10n {
    static func tr(_ source: String, language: AppLanguage? = nil) -> String {
        let selected = language ?? LanguageController.shared.resolvedLanguage
        let resolved = selected == .system ? AppLanguage.resolve(preferredLanguages: Locale.preferredLanguages) : selected
        return resolved == .english ? english[source] ?? source : source
    }

    static func format(_ source: String, _ arguments: CVarArg...) -> String {
        String(format: tr(source), locale: LanguageController.shared.locale, arguments: arguments)
    }

    static let english: [String: String] = [
        "剪贴板": "Clipboard", "本次运行 · 每类最多 50 条": "This session · Up to 50 per category",
        "继续记录": "Resume", "暂停记录": "Pause", "图片": "Images", "文字": "Text",
        "清空": "Clear", "删除": "Delete", "尚无复制的图片": "No copied images yet",
        "尚无复制的文字": "No copied text yet", "已复制": "Copied", "复制图片": "Copy Image",
        "点击重新复制，右键删除": "Click to copy again; right-click to delete",
        "复制失败，请重试": "Copy failed. Try again.",
        "拖动桌面卡片可调整并保存布局。Esc 取消拖动，再按一次收起；未拖动时直接收起。": "Drag desktop cards to adjust and save the layout. Esc cancels a drag; press again to dismiss. When not dragging, Esc dismisses immediately.",
        "搜索项目": "Search Projects", "网格布局预览…": "Preview Grid Layout…", "关系布局预览…": "Preview Relationship Layout…", "创建区域…": "Create Region…", "编辑区域…": "Edit Region…", "选择区域成员": "Select Region Members", "移除区域（保留卡片）": "Remove Region (Keep Cards)", "备注与链接…": "Notes and Links…",
        "搜索所有项目组": "Search All Groups", "项目名称或路径": "Project name or path", "没有匹配的项目": "No Matching Projects", "↑↓ 选择 · 回车打开 · ⌘回车定位": "↑↓ Select · Return Open · ⌘Return Locate", "定位到画布": "Locate on Canvas",
        "项目备注与链接（所有项目组共享）": "Project notes and links (shared across groups)", "项目备注": "Project Notes", "链接": "Links", "添加链接": "Add Link", "打开链接": "Open Link", "移除链接": "Remove Link", "链接需要名称和有效的 HTTP 或 HTTPS 地址。": "Links require a name and a valid HTTP or HTTPS address.",
        "从选中卡片创建区域": "Create Region from Selected Cards", "编辑区域": "Edit Region", "区域名称": "Region Name", "颜色": "Color", "拖动区域标题可一起移动成员；移除区域会保留卡片。": "Drag the region title to move its cards together. Removing a region keeps its cards.", "布局预览": "Layout Preview", "当前手动布局保持不变。只有点击应用后才会保存，可一次撤销。": "Your current layout stays unchanged until you apply. Applying can be undone in one step.", "应用布局": "Apply Layout", "画布已更改，请重新生成布局预览。": "The canvas has changed. Generate a new layout preview.",

        "画布数据版本不受支持。原文件已保留。": "This canvas data version is unsupported. The original file has been preserved.", "画布数据包含重复标识或无效引用。原文件已保留。": "Canvas data contains duplicate identifiers or invalid references. The original file has been preserved.", "原数据无法读取，已暂停保存。请从备份恢复。": "The original data could not be read. Saving is paused. Please restore a backup.", "没有可用的有效备份。": "No valid backup is available.",

        "桌面外观": "Desktop Appearance", "模糊背景强度": "Background Blur", "背景暗度": "Background Dimming", "卡片大小": "Card Size", "%d%% · 内容较多时会自动缩小以适应屏幕。": "%d%% · Automatically shrinks to fit when needed.", "显示连线标签": "Show Connection Labels", "恢复默认外观": "Reset Appearance",
        "文件夹不存在，请右键卡片选择“重新定位文件夹”。": "The folder is missing. Right-click the card and choose Relocate Folder.", "无法打开文件夹。": "Unable to open the folder.", "找不到 %@，请安装应用或更改打开方式。": "%@ was not found. Install the app or choose another application.", "编辑器启动失败：%@": "Editor launch failed: %@", "干净": "Clean", "%d 项变更": "%d changes", "非 Git 仓库 / 不可读取": "Not a Git repository / Unreadable", "Git 状态不可用": "Git status unavailable",

        "跟随系统": "System", "语言": "Language", "设置": "Settings", "取消": "Cancel", "保存": "Save", "完成": "Done", "好": "OK",
        "重命名": "Rename", "名称": "Name", "我的项目": "My Projects", "新建组": "New Group", "项目": "Project", "项目组": "Groups",
        "默认": "Default", "蓝色": "Blue", "绿色": "Green", "橙色": "Orange", "粉色": "Pink", "紫色": "Purple",
        "依赖": "Dependency", "调用": "Call", "配置": "Configuration", "关联": "Related",
        "桌面背景层（位于普通窗口后面）": "Desktop background (behind regular windows)", "当前桌面前置覆盖": "Foreground overlay on current desktop",
        "原数据无法读取，保存已暂停。可恢复备份或导入已导出的数据。": "Your data could not be read. Saving is paused. Restore a backup or import an export.",
        "恢复备份": "Restore Backup", "导入…": "Import…", "还没有项目组": "No Project Groups Yet",
        "恢复最近的有效备份？当前文件会另存保留。": "Restore the latest valid backup? The current file will be preserved separately.",
        "新建项目组": "New Project Group", "导出项目组…": "Export Group…", "删除项目组": "Delete Group", "导入项目组…": "Import Group…", "导出当前项目组…": "Export Current Group…", "从最近备份恢复…": "Restore Latest Backup…", "导入、导出与恢复": "Import, Export and Recovery",
        "数据保存在这台 Mac 上\n⌘⇧空格 呼出/收起桌面卡片": "Data is saved on this Mac\n⌘⇧Space toggles desktop cards",
        "添加项目文件夹": "Add Project Folders", "从 Finder 拖入，或点击下方按钮。": "Drag folders from Finder or use the button below.", "选择文件夹": "Choose Folders",
        "先点起点，再点终点": "Select the source, then the destination", "点击终点完成连线": "Select the destination to connect", "显示全部": "Show All", "回到内容": "Return to Content",
        "添加文件夹（⇧⌘O）": "Add Folders (⇧⌘O)", "显示或隐藏桌面卡片（⌘⇧空格）": "Show or Hide Desktop Cards (⌘⇧Space)", "刷新 Git 状态": "Refresh Git Status", "编辑": "Edit", "撤销": "Undo", "重做": "Redo",
        "布局": "Layout", "自动布局": "Auto Layout", "对齐到网格": "Align to Grid", "拖动吸附": "Snap While Dragging", "背景颜色": "Background Color", "取消连线": "Cancel Connection", "连线": "Connect", "关系": "Relationships", "显示连线": "Show Connections", "高亮": "Highlight", "全部": "All", "选中项目的上游": "Upstream of Selection", "选中项目的下游": "Downstream of Selection", "连线属性": "Connection Properties", "拖框选择 · ⇧ 追加": "Drag to select · ⇧ to extend", "已选 %d 张": "%d selected", "删除选中项": "Delete Selection", "重新定位 %@": "Relocate %@",
        "拖动移动；⇧ 点击多选": "Drag to move; ⇧ click to select multiple", "点击打开 · 右键设置": "Click to open · Right-click for settings", "打开项目": "Open Project", "在 Finder 中显示": "Show in Finder", "复制路径": "Copy Path", "打开方式…": "Open With…", "重新定位文件夹…": "Relocate Folder…", "卡片背景": "Card Background", "重命名卡片": "Rename Card", "从此组移除": "Remove from Group", "关闭桌面覆盖": "Close Desktop Overlay",
        "默认打开方式": "Default Application", "编辑器默认使用新窗口": "Open Editors in a New Window by Default", "新窗口 / 复用窗口适用于 VS Code 和 Cursor；其他应用使用自身窗口偏好。项目可单独覆盖默认设置。": "New/reused windows apply to VS Code and Cursor. Other apps use their own preferences. Projects can override these defaults.", "桌面显示": "Desktop Display", "显示器": "Display", "当前显示器": "Current Display", "应用快捷键：⌘⇧空格，显示或隐藏卡片、连线与模糊背景。前置覆盖模式下，成功打开项目后自动收起。Fn-F11 仅执行 macOS 原生“显示桌面”。": "Shortcut: ⌘⇧Space toggles cards, connections and background blur. Foreground overlay closes after opening a project. Fn-F11 retains the native macOS Show Desktop action.",
        "%@ · 打开方式": "%@ · Open With", "应用": "Application", "跟随默认（%@）": "Use Default (%@)", "窗口": "Window", "跟随默认": "Use Default", "新窗口": "New Window", "复用窗口": "Reuse Window", "窗口选项适用于 VS Code / Cursor。设置在所有组中共享。": "Window options apply to VS Code / Cursor. Settings are shared across groups.", "方向：先选的卡片 → 后选的卡片": "Direction: first card → second card", "关系类型": "Relationship Type", "标签（可选，最多 120 字）": "Label (optional, up to 120 characters)",
        "导入项目组": "Import Group", "选择导出的 JSON 文件…": "Choose Exported JSON File…", "换电脑时可替换路径前缀；留空保留原路径。导入会新增组，不覆盖已有组。": "Replace the path prefix when moving to another Mac, or leave blank to keep paths. Import adds groups without replacing existing groups.", "原路径前缀，例如 /Users/old/Code": "Original path prefix, e.g. /Users/old/Code", "新路径前缀，例如 /Users/me/Code": "New path prefix, e.g. /Users/me/Code", "导入后会恢复保存；原文件将另存保留。": "Import will resume saving. The original file will be preserved separately.", "导入": "Import",
        "加载失败，原文件已保留，已暂停保存：%@": "Loading failed. The original file is preserved and saving is paused: %@", "请选择或拖入文件夹。": "Choose or drag in a folder.", "保存失败：%@": "Saving failed: %@", "请选择有效的文件夹。": "Choose a valid folder.", "此文件夹已属于另一个项目。": "This folder already belongs to another project.", "导出失败：%@": "Export failed: %@", "文件中没有可导入的项目组。": "The file contains no groups to import.", "导入失败：%@": "Import failed: %@", "恢复失败：%@": "Restore failed: %@"
    ]
}
