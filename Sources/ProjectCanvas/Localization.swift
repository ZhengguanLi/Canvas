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
        selection = AppLanguage(rawValue: preferences.string(forKey: Self.preferenceKey) ?? "") ?? .english
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
        "不限条数": "Unlimited", "不限条数仍受内存上限保护。": "Unlimited item counts still respect memory limits.",
        "上限：图片 %@ · 文字 %@": "Limits: %@ images · %@ text",
        "上限：图片 %d · 文字 %d": "Limits: %d images · %d text",
        "剪贴板设置": "Clipboard Settings",
        "历史数量上限": "History Limits",
        "图片上限：%d 条": "Images: up to %d items",
        "文字上限：%d 条": "Text: up to %d items",
        "降低上限会删除最旧的历史记录，已放入画布的内容不受影响。": "Lowering a limit removes the oldest history items. Content placed on a canvas is kept.",
        "恢复默认数量": "Reset History Limits",
        "本次运行 · 图片最多 %d 条，文字最多 %d 条": "This session · Up to %d images and %d text items",
        "工作区": "Workspace",
        "快速访问": "Quick Access",
        "数据保存在这台 Mac 上 · ⌘⇧空格 显示桌面卡片": "Data is saved on this Mac · ⌘⇧Space shows desktop cards",
        "从 Finder 拖入项目文件夹，或将上方剪贴板内容拖到这里。": "Drag project folders from Finder, or drag clipboard content here from above.",
        "点击复制；拖入画布，或右键放入画布": "Click to copy; drag onto the canvas or right-click to place",
        "放入当前画布": "Place on Current Canvas", "复制内容": "Copy Content",
        "画布内容已达到 64 MB，请先删除部分图片或文字。": "Canvas content has reached 64 MB. Remove some images or text first.",
        "拖框选择 · Ctrl / ⇧ 追加": "Drag to select · Ctrl / ⇧ to extend",
        "连接到 %@": "Connect to %@", "拖动移动；Ctrl / ⇧ 点击多选": "Drag to move; Ctrl / ⇧ click to select multiple",
        "示例": "Sample", "示例图片": "Sample image",
        "仅用于预览，桌面模式显示真实剪贴板内容。": "Preview only. Desktop mode shows your actual clipboard history.",
        "记录一个想法，稍后继续。": "Capture an idea and come back to it later.",
        "待办事项：整理项目、查看文档。": "To do: organize projects and review documentation.",
        "常用片段会挂在这里，方便随时取用。": "Keep useful snippets here for quick access.",
        "通用": "General", "桌面": "Desktop", "内容较多时会自动缩小以适应屏幕。": "Content scales down to fit the display when needed.",
        "剪贴板显示": "Clipboard Display", "默认宽度": "Default Width", "左右展开": "Full Width", "不展示": "Hidden",
        "剪贴板显示大小": "Clipboard Display Size", "图片预览大小": "Image Preview Size",
        "文字字号": "Text Size", "恢复默认大小": "Reset Sizes",
        "无色": "No Tint", "浅灰": "Light Gray", "暖色": "Warm",
        "自定义颜色": "Custom Color", "颜色浓度": "Color Intensity", "磨砂背景颜色": "Frosted Background Color",
        "画布背景": "Canvas Background", "颜色和浓度同时应用于内容区与桌面磨砂背景。": "Color and intensity apply to both the canvas and the frosted desktop background.",
        "自定义颜色…": "Custom Color…",
        "项目名称、路径或标签": "Project name, path or tag",
        "项目详情…": "Project Details…", "项目详情（所有项目组共享）": "Project details (shared across groups)",
        "标签（用逗号分隔）": "Tags (comma separated)", "备注与标签": "Notes and Tags",
        "启动配置": "Launch Configurations", "添加启动配置": "Add Launch Configuration",
        "在 Terminal 中运行，工作目录默认为项目文件夹。": "Run in Terminal. The working directory defaults to the project folder.",
        "启动配置需要名称、命令和有效的环境变量名称。": "Launch configurations require a name, a command and valid environment variable names.",
        "启动工作目录不存在，请检查启动配置。": "The working directory is missing. Check the launch configuration.",
        "命令": "Command", "工作目录（留空使用项目目录，可填写相对路径）": "Working directory (blank for project folder; relative paths supported)",
        "环境变量": "Environment Variables", "添加变量": "Add Variable", "值": "Value",
        "环境变量名称不能为空或重复。": "Environment variable names cannot be empty or repeated.",
        "命令使用 zsh 执行；环境变量以明文保存在本机项目数据及导出文件中。": "Commands run in zsh. Environment variables are saved as plain text in local project data and exports.",
        "运行": "Run", "最近打开": "Recently Opened", "常用项目": "Frequent Projects",
        "打开项目后显示在这里": "Projects appear here after opening", "打开 %d 次": "Opened %d times",
        "标签筛选": "Filter by Tag", "全部标签": "All Tags", "清除筛选": "Clear Filter",
        "显示 %d / %d 个项目": "Showing %d of %d projects",
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
        "先点起点，再点终点": "Select the source, then the destination", "点击终点完成连线": "Select the destination to connect", "缩小": "Zoom Out", "放大": "Zoom In", "缩放比例": "Zoom Level", "适应视图": "Fit to View", "回到卡片": "Back to Cards",
        "添加文件夹（⇧⌘O）": "Add Folders (⇧⌘O)", "显示或隐藏桌面卡片（⌘⇧空格）": "Show or Hide Desktop Cards (⌘⇧Space)", "刷新 Git 状态": "Refresh Git Status", "编辑": "Edit", "撤销": "Undo", "重做": "Redo",
        "布局": "Layout", "自动布局": "Auto Layout", "对齐到网格": "Align to Grid", "拖动吸附": "Snap While Dragging", "对齐卡片": "Align to Cards", "背景颜色": "Background Color", "取消连线": "Cancel Connection", "连线": "Connect", "关系": "Relationships", "显示连线": "Show Connections", "高亮": "Highlight", "全部": "All", "选中项目的上游": "Upstream of Selection", "选中项目的下游": "Downstream of Selection", "连线属性": "Connection Properties", "拖框选择 · ⇧ 追加": "Drag to select · ⇧ to extend", "已选 %d 张": "%d selected", "删除选中项": "Delete Selection", "重新定位 %@": "Relocate %@",
        "拖动移动；⇧ 点击多选": "Drag to move; ⇧ click to select multiple", "点击打开 · 右键设置": "Click to open · Right-click for settings", "打开项目": "Open Project", "在 Finder 中显示": "Show in Finder", "复制路径": "Copy Path", "打开方式…": "Open With…", "重新定位文件夹…": "Relocate Folder…", "卡片背景": "Card Background", "重命名卡片": "Rename Card", "从此组移除": "Remove from Group", "关闭桌面覆盖": "Close Desktop Overlay",
        "默认打开方式": "Default Application", "编辑器默认使用新窗口": "Open Editors in a New Window by Default", "新窗口 / 复用窗口适用于 VS Code 和 Cursor；其他应用使用自身窗口偏好。项目可单独覆盖默认设置。": "New/reused windows apply to VS Code and Cursor. Other apps use their own preferences. Projects can override these defaults.", "桌面显示": "Desktop Display", "显示器": "Display", "当前显示器": "Current Display", "应用快捷键：⌘⇧空格，显示或隐藏卡片、连线与模糊背景。前置覆盖模式下，成功打开项目后自动收起。Fn-F11 仅执行 macOS 原生“显示桌面”。": "Shortcut: ⌘⇧Space toggles cards, connections and background blur. Foreground overlay closes after opening a project. Fn-F11 retains the native macOS Show Desktop action.",
        "%@ · 打开方式": "%@ · Open With", "应用": "Application", "跟随默认（%@）": "Use Default (%@)", "窗口": "Window", "跟随默认": "Use Default", "新窗口": "New Window", "复用窗口": "Reuse Window", "窗口选项适用于 VS Code / Cursor。设置在所有组中共享。": "Window options apply to VS Code / Cursor. Settings are shared across groups.", "方向：先选的卡片 → 后选的卡片": "Direction: first card → second card", "关系类型": "Relationship Type", "标签（可选，最多 120 字）": "Label (optional, up to 120 characters)",
        "返回顶部剪贴板": "Return to Top Shelf", "全屏浏览剪贴板": "Browse Clipboard Full Screen",
        "恢复默认宽度": "Restore Default Width", "展开至屏幕宽度": "Expand to Screen Width",
        "导入项目组": "Import Group", "选择导出的 JSON 文件…": "Choose Exported JSON File…", "换电脑时可替换路径前缀；留空保留原路径。导入会新增组，不覆盖已有组。": "Replace the path prefix when moving to another Mac, or leave blank to keep paths. Import adds groups without replacing existing groups.", "原路径前缀，例如 /Users/old/Code": "Original path prefix, e.g. /Users/old/Code", "新路径前缀，例如 /Users/me/Code": "New path prefix, e.g. /Users/me/Code", "导入后会恢复保存；原文件将另存保留。": "Import will resume saving. The original file will be preserved separately.", "导入": "Import",
        "加载失败，原文件已保留，已暂停保存：%@": "Loading failed. The original file is preserved and saving is paused: %@", "请选择或拖入文件夹。": "Choose or drag in a folder.", "保存失败：%@": "Saving failed: %@", "请选择有效的文件夹。": "Choose a valid folder.", "此文件夹已属于另一个项目。": "This folder already belongs to another project.", "导出失败：%@": "Export failed: %@", "文件中没有可导入的项目组。": "The file contains no groups to import.", "导入失败：%@": "Import failed: %@", "恢复失败：%@": "Restore failed: %@"
    ]
}
