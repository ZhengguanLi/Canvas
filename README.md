# ProjectCanvas

ProjectCanvas is a standalone macOS 26+ app for organizing local project folders on a visual canvas and opening them in your preferred development tools.

## Projects and opening

- Create, rename, switch, export, and import project groups. A folder can appear in several groups with its own name, color, and position in each.
- Add folders with the picker or drag them from Finder onto the canvas.
- In the main window, click a card to select it and drag to move it. Right-click for **Open Project**, **Open With**, **Show in Finder**, **Copy Path**, **Relocate Folder**, and **Card Background**. Desktop cards still open projects when clicked.
- Set a default application in **Settings**: VS Code, Cursor, IntelliJ IDEA, Finder, or Terminal. Each project can override it.
- VS Code and Cursor support new/reused windows. IntelliJ and Terminal use their own window preferences.
- Cards display Git branch, changed-file count, and linked-worktree status. Status refreshes in the background on activation, approximately every minute, or with the refresh button. Git must be available through `/usr/bin/git`. Up to three repositories refresh concurrently; each Git command has a 15-second timeout.

## Canvas and relationships

- Use **画布背景 / Canvas Background** in the canvas toolbar to choose no tint, light gray, blue, warm or a custom color, and adjust its intensity. The canvas and desktop share the same color and intensity; changes from either entry apply immediately to both and persist across restarts. This palette applies across project groups. Older settings migrate automatically, keeping the canvas choice when both palettes were previously configured.
- Right-click an empty part of the canvas to switch background presets, open the custom color controls, add folders or show all cards. Project cards and regions retain their own context menus.
- Press **⌘K** to search project names and paths across groups; open a result or locate its card on the canvas.
- Create named, colored regions from selected cards. Drag a region header to move its cards together; removing a region keeps its cards.
- Use a card's **Project Details…** action to edit notes, named web links, tags and launch configurations. These details are shared across groups.
- Tags are comma separated, trimmed and deduplicated without regard to case. Cards display their tags. Use the canvas tag picker to filter projects; connections and regions show only visible members. Locating a project clears the filter so the target is visible. Filtering preserves saved card positions. **⌘K** searches tags as well as names and paths.
- The main canvas is always editable: click to select, drag to move, or marquee-select several cards. ⌘/Shift-click or ⌘/Shift-marquee adds to the selection; Control-click opens the context menu as usual. Ctrl+A or ⌘A selects all visible cards. With exactly two cards selected, right-click either and choose **Connect to …** to draw a directed connection from that card to the other. Clicking a canvas card selects it; opening projects and copying canvas content use the context menu.
- Selected cards and their connections preview movement together; dragging preserves relative spacing. Nearby card edges and center lines show alignment guides and snap within six screen points. Use **Layout → Align to Cards** to toggle this; card alignment takes priority over grid snapping.
- Choose **Background Color** for a selection, or use a card's context menu. Six choices are available, including the default background. Colors also appear on desktop cards.
- Use **Layout** to preview a grid or directed relationship layout. A preview does not change saved card positions. **Apply** commits one undoable operation; canceling or closing keeps your manual layout. If the canvas changes while the preview is open, generate a fresh preview. Grid alignment and drag snapping remain available.
- Create directed connections by selecting the source and destination. Reverse connections are supported and drawn on separate curves. Select a connection and choose **Connection Properties** to assign a type and label.
- **Relationships** controls visibility and highlights the selected projects' transitive upstream/downstream relationships.
- Canvas bounds grow with content. **Fit to View** fits the clotheslines and cards together and adapts them when the window resizes; **Back to Cards** returns to the top of the shared content, including the clotheslines, at the current zoom. The clotheslines share canvas zoom and scrolling. Zoom and scroll position are remembered separately per group.
- Undo/redo covers card colors, movement, layout, connections, project options, and group changes. Bulk folder additions and bulk card removal each form one undo operation.

## Launch configurations and usage

- In **Project Details → Launch Configurations**, save multiple named commands for each project, with an optional working directory and environment variables. A blank working directory uses the project folder; relative paths resolve against that folder. Environment variable names must use letters, digits and underscores and cannot begin with a digit.
- Right-click a canvas card and choose **Run → configuration name** to execute it in Terminal using zsh. Opening the project normally still uses its configured editor. Commands execute only when explicitly selected; imported configurations do not run automatically.
- Paths and environment values are passed literally. Environment variables are stored as plain text in local canvas data, backups and exports. A temporary launch script is created in a private directory and removes itself when Terminal starts it. Command output and failures remain visible in Terminal; handing the script to Terminal counts as opening the project, regardless of the command's eventual exit status.
- The sidebar's **Recently Opened** and **Frequent Projects** sections each show up to eight unique projects still present in a group. Click to open, or use the target button to locate the card. Recent projects sort by last successful open; frequent projects sort by open count, then recency. Usage is saved across app restarts, and opening failures do not increment it.
- Usage updates do not rotate recovery backups or create undo steps. Undo/redo of project edits preserves current usage for projects that remain in the collection.

## Desktop cards

- Toggle desktop cards from the toolbar or use **⇧⌘C** globally while the app is running. Change the shortcut in **Settings ▸ Desktop Display**.
- Desktop cards include directed, labeled connections and a blurred background. Connection visibility follows **Relationships → Show Connections**.
- **Fn-F11** retains macOS native Show Desktop behavior; the app shortcut defaults to **⇧⌘C**.
- Settings offer desktop-background and foreground-overlay modes, plus a fixed monitor or the current monitor. A disconnected fixed monitor falls back to the current one.
- Foreground overlay closes after a project opens successfully or when you switch to another application. A close button also dismisses it.
- Clicking the blurred background outside the cards (including connections) dismisses the desktop display.
- Drag desktop cards to adjust the same layout shown in the main canvas. Release saves one undoable move; connection lines follow the preview. A drag never opens the project.
- **Escape** cancels an active drag without saving. Press it again, or press it while idle, to dismiss desktop display. Escape is released for other apps when desktop display is hidden.
- Switching display modes updates existing card windows. Card colors match the canvas palette.
- Desktop appearance settings adjust the native blur blend, background dimming, scene size and connection-label visibility. The scene still shrinks to fit the selected screen when necessary.
- **Settings → Desktop Appearance → Frosted Background Color** edits the same color and intensity used by the canvas. On the desktop, the tint sits above the blur and below dimming and connection lines. **No Tint** clears both backgrounds; **Reset Appearance** also resets the shared tint.
- If another app owns the global shortcut, the toolbar remains available.

## Clipboard shelf

Images and text hang from separate clotheslines with metallic clips and softly tilted cards, inspired by CopyHang. Hovering gently straightens a card; Reduce Motion disables the tilt and animation.

- The foreground desktop overlay shows actual clipboard images and text on two clotheslines with independent horizontal scrolling. Newly copied content appears first; duplicate content moves to the front. The main window shows fixed image and text samples to preview the layout and sizing; these samples cannot be copied, deleted, or placed on the canvas.
- Clotheslines share the desktop backdrop above the project cards. Copying, deleting, and scrolling do not dismiss the overlay. Escape closes the overlay. Clotheslines remain available in an empty project group.
- On the desktop, click an item to copy it again or right-click to delete it. Desktop clotheslines hide category labels and control buttons; use the main window category menus and Settings to configure their appearance.
- History is kept only for this app session, with separate image and text limits (25, 50, 100, or Unlimited; default 50), and is never written to canvas data or imported from CopyHang. Recording starts with new clipboard changes, not pre-existing contents.
- Private, temporary, automatically generated and Finder file payloads are excluded. Plain text takes precedence when an application also supplies a picture of that text.
- Individual entries are limited to 256 KiB of text or 8 MiB of image data (32 million pixels); category memory budgets can reduce the retained count. Images decode in the background into small previews.

Use a main-window sample category menu’s **Clipboard Settings** action to adjust image previews (100–200%) and text (11–24 pt) independently. Both settings persist and apply to the top shelf and full-screen grid.

The clipboard display menu in the main toolbar, shelf header, and Settings offers **Default Width**, **Full Width**, and **Hidden**. These preferences apply to both the main window and desktop overlay and are preserved across launches. Hiding the shelf restores space for the canvas; the toolbar menu remains available to show it again.

History limits are available in Clipboard Settings and app Settings. Lowering a limit immediately removes the oldest items in that category; content already placed on a canvas is preserved. Unlimited removes the item-count cap while preserving the category memory budgets. Limits persist across launches, while history itself remains session-only.

## Clipboard content on the canvas

- Drag an image or text item from a clothesline onto the main canvas or desktop background, or right-click it and choose **Place on Current Canvas**. Existing card positions stay unchanged.
- Placed content becomes a card in the selected group. Move, multi-select, color, connect, group into regions, or remove it alongside project cards. Grid and relationship layout previews include content cards and remain optional to apply.
- Main-window canvas cards select when clicked; use their context menus to copy content or open projects. Desktop content cards copy their original text or image when clicked; desktop project cards open their configured application. Desktop cards support dragging.
- Explicitly placed content is saved in canvas data, backups, and group exports. Clearing session clipboard history does not remove it. Undo/redo covers adding, moving, and removing content cards.
- Images retain their original bytes plus a small preview. Each group can retain up to 64 MiB of explicit clipboard content; per-item clipboard limits still apply. Clipboard history remains session-only and is never added to the canvas automatically.

## Local data, backup, and transfer

Data is saved at `~/Library/Application Support/ProjectCanvas/canvas.json`.

- Legacy canvas files remain readable. Schema versions and card/connection references are validated.
- Invalid or unreadable files are preserved, and saving pauses until recovery. The recovery banner offers backup restoration or JSON import.
- Encoding, validation and writes run on a serial background queue. Viewport updates are coalesced after 300 ms; normal app termination flushes pending writes. Recovery operations wait for earlier writes and discard pending viewport changes.
- The five most recent changed, valid pre-edit snapshots are retained as `canvas.json.backup1` through `canvas.json.backup5`. Scrolling, zooming, and group selection do not rotate these backups.
- Restoring a backup or importing during recovery preserves the previous file as `canvas.json.preserved-<UUID>`.
- **Import, Export and Recovery** exports the selected group or imports groups into the current collection. Import generates fresh group/card/connection IDs and reuses projects with the same path.
- Optional path-prefix mapping supports moving exports between machines. Missing folders can also be repaired individually through **Relocate Folder**.
- Exports contain local folder paths. Repository contents are not copied.

The clipboard shelf’s expand button uses the full available screen width while keeping the same height and separate, horizontally scrolling image and text rows. A separate full-screen button opens image and text grids with independent scrolling. Escape returns from full-screen browsing to the top shelf while preserving the width setting; otherwise it closes the desktop overlay.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Add folders | ⇧⌘O |
| Select all visible canvas cards | ⌃A / ⌘A |
| Undo / redo | ⌘Z / ⇧⌘Z |
| Settings | ⌘, |
| Search all projects | ⌘K |
| Toggle desktop cards | ⇧⌘C (customizable) |
| Clear selection / cancel connection | Escape |
| Remove selected canvas items | Delete |

## Language

English is the default for new installations. Choose **System**, **Simplified Chinese**, or **English** in Settings. Application copy changes immediately and the preference persists. Project names, notes, custom link titles and connection labels remain as entered. Native macOS dialogs follow the operating system's language.

## Build and verify

```bash
swift test
bash scripts/build-app.sh
open build/ProjectCanvas.app
```

The build script creates a locally ad-hoc-signed application. VS Code and Cursor are located through their installed application bundles, common command directories, or PATH. The project uses SwiftUI/AppKit and has no third-party package dependencies.

Tests use temporary canvas files and temporary Git repositories. They cover legacy/corrupt data, recovery, import/export, path mapping, colors, opening options, viewport persistence, directed relationships, undo/redo, Git parsing/worktrees, and native canvas scrolling.
