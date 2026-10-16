# ProjectCanvas

ProjectCanvas is a standalone macOS 14+ app for organizing local project folders on a visual canvas and opening them in your preferred development tools.

## Projects and opening

- Create, rename, switch, export, and import project groups. A folder can appear in several groups with its own name, color, and position in each.
- Add folders with the picker or drag them from Finder onto the canvas.
- Click a card to open it. Right-click for **打开方式**, **在 Finder 中显示**, **复制路径**, **重新定位文件夹**, and **卡片背景**.
- Set a default application in **设置**: VS Code, Cursor, IntelliJ IDEA, Finder, or Terminal. Each project can override it.
- VS Code and Cursor support new/reused windows. IntelliJ and Terminal use their own window preferences.
- Cards display Git branch, changed-file count, and linked-worktree status. Status refreshes in the background on activation, approximately every minute, or with the refresh button. Git must be available through `/usr/bin/git`.

## Canvas and relationships

- Press **⌘K** to search project names and paths across groups; open a result or locate its card on the canvas.
- Create named, colored regions from selected cards. Drag a region header in edit mode to move its cards together; removing a region keeps its cards.
- Use a card's details action to edit project notes and named web links. These details are shared across groups.
- Enter **编辑** to select or move cards without opening them. Marquee selection works even when there are no visible connections. Shift-click or Shift/Control-marquee adds to the selection.
- Selected cards and their connections preview movement together; grid snapping preserves relative spacing.
- Choose **背景颜色** for a selection, or use a card's context menu. Six choices are available, including the default background. Colors also appear on desktop cards.
- Use **布局** to preview a grid or directed relationship layout. A preview does not change saved card positions. **Apply** commits one undoable operation; canceling or closing keeps your manual layout. If the canvas changes while the preview is open, generate a fresh preview. Grid alignment and drag snapping remain available.
- Create directed connections by selecting the source and destination. Reverse connections are supported and drawn on separate curves. Select a connection and choose **连线属性** to assign a type and label.
- **关系** controls visibility and highlights the selected projects' transitive upstream/downstream relationships.
- Canvas bounds grow with content. **显示全部** fits the current content; **回到内容** returns to its origin. Zoom and scroll position are remembered separately per group.
- Undo/redo covers card colors, movement, layout, connections, project options, and group changes. Bulk folder additions and bulk card removal each form one undo operation.

## Desktop cards

- Toggle desktop cards from the toolbar or use **⌘⇧Space** globally while the app is running.
- Desktop cards include directed, labeled connections and a blurred background. Connection visibility follows **关系 → 显示连线**.
- **Fn-F11** retains macOS native Show Desktop behavior; the app shortcut is **⌘⇧Space**.
- Settings offer desktop-background and foreground-overlay modes, plus a fixed monitor or the current monitor. A disconnected fixed monitor falls back to the current one.
- Foreground overlay closes after a project opens successfully. A close button also dismisses it.
- Clicking the blurred background outside the cards (including connections) dismisses the desktop display.
- Drag desktop cards to adjust the same layout shown in the main canvas. Release saves one undoable move; connection lines follow the preview. A drag never opens the project.
- **Escape** cancels an active drag without saving. Press it again, or press it while idle, to dismiss desktop display. Escape is released for other apps when desktop display is hidden.
- Switching display modes updates existing card windows. Card colors match the canvas palette.
- Desktop appearance settings adjust the native blur blend, background dimming, scene size and connection-label visibility. The scene still shrinks to fit the selected screen when necessary.
- If another app owns the global shortcut, the toolbar remains available.

## Clipboard shelf

- The foreground desktop overlay has separate **Images** and **Text** rows at the top, with counts and independent horizontal scrolling. Newly copied content appears first; duplicate content moves to the front. The main window does not show this shelf.
- The shelf has its own interactive panel above the cards: copying, deleting and scrolling do not dismiss the overlay. Collapse it to leave more room for projects, or close it with the close button or Escape. It remains available even in an empty project group.
- Click an item to copy it again, right-click to delete it, or clear a category. Pause/resume recording or collapse the shelf from its header.
- History is kept only for this app session, up to 50 items per category, and is never written to canvas data or imported from CopyHang. Recording starts with new clipboard changes, not pre-existing contents.
- Private, temporary, automatically generated and Finder file payloads are excluded. Plain text takes precedence when an application also supplies a picture of that text.
- Individual entries are limited to 256 KiB of text or 8 MiB of image data (32 million pixels); category memory budgets can reduce the retained count. Images decode in the background into small previews.

## Local data, backup, and transfer

Data is saved at `~/Library/Application Support/ProjectCanvas/canvas.json`.

- Legacy canvas files remain readable. Schema versions and card/connection references are validated.
- Invalid or unreadable files are preserved, and saving pauses until recovery. The recovery banner offers backup restoration or JSON import.
- The five most recent changed, valid pre-edit snapshots are retained as `canvas.json.backup1` through `canvas.json.backup5`. Scrolling, zooming, and group selection do not rotate these backups.
- Restoring a backup or importing during recovery preserves the previous file as `canvas.json.preserved-<UUID>`.
- **导入、导出与恢复** exports the selected group or imports groups into the current collection. Import generates fresh group/card/connection IDs and reuses projects with the same path.
- Optional path-prefix mapping supports moving exports between machines. Missing folders can also be repaired individually through **重新定位文件夹**.
- Exports contain local folder paths. Repository contents are not copied.

The clipboard shelf’s expand button fills the desktop overlay with separate image and text grids, each with its own scrolling. Use the restore button to return to the top shelf; Escape closes the overlay.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Add folders | ⇧⌘O |
| Undo / redo | ⌘Z / ⇧⌘Z |
| Settings | ⌘, |
| Search all projects | ⌘K |
| Toggle desktop cards | ⌘⇧Space |
| Clear selection / cancel connection | Escape |
| Remove selected items in edit mode | Delete |

## Language

Choose **System**, **简体中文**, or **English** in Settings. Application copy changes immediately and the preference persists. Project names, notes, custom link titles and connection labels remain as entered. Native macOS dialogs follow the operating system's language.

## Build and verify

```bash
swift test
bash scripts/build-app.sh
open build/ProjectCanvas.app
```

The build script creates a locally ad-hoc-signed application. VS Code and Cursor are located through their installed application bundles, common command directories, or PATH. The project uses SwiftUI/AppKit and has no third-party package dependencies.

Tests use temporary canvas files and temporary Git repositories. They cover legacy/corrupt data, recovery, import/export, path mapping, colors, opening options, viewport persistence, directed relationships, undo/redo, Git parsing/worktrees, and native canvas scrolling.
