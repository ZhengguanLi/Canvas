# ProjectCanvas Workbench Implementation Plan

**Goal:** Implement the accepted reliability fixes, editor configuration, Git summaries, directed relationships, card colors, and usability improvements.
**Architecture:** Keep SwiftUI/AppKit. Separate durable storage, launch command construction and background Git inspection from view code. Preserve existing JSON and all user files.
**Constraints:** macOS 14+, no external dependencies; Chinese UI. No commits of pre-existing untracked user sources. Existing repository has no initial commit, so work in place with a source backup rather than fabricate a baseline commit for a worktree.

## Tasks
- [x] Data/model: versioned backward-compatible decoding, preserve invalid input, rotating validated backups/recovery, selection and viewport persistence, import/export/remap, color and typed directed links. Add regression tests and observe failures before fixes.
- [x] Services: editor defaults/overrides and launch modes; async Git summary with branch, changes and worktree; missing-folder checks and process failure reporting. Test commands/parser against literal expectations.
- [x] Canvas/UI: always-available marquee, dynamic extent, fit/home, shared drag preview, compact contextual toolbar, colors, relationship labels/directions/highlight, Finder drop/actions, settings and transfer/recovery UI.
- [x] Desktop: state ordering, level refresh, color rendering, hotkey activation, auto-hide on opening, selected display persistence and incremental view refresh.
- [x] Automated integration: all Swift tests and release build pass; primary-agent diff review and README update complete.
- [x] App-bundle packaging and independent review completed after quota recovery.
- [ ] Live desktop/editor interaction acceptance: UI automation cannot bind the running app; monitor and editor interactions remain unverified.

## Verification
Use temporary storage and repositories for tests, never live user canvas. Cover corrupted/legacy/future data, recovery, selection persistence, undo/redo, connection cleanup/direction, launch options and Git parsing. Build the app bundle after tests. Manually inspect the UI if available; record any unverified OS interactions.

## Execution record

- Feature branch: `codex/workbench-improvements`; original source backup: `/private/tmp/ProjectCanvas-before-20261015`.
- Initial regression run reproduced corrupt-file overwrite, selection loss, and rejected reverse edges. All were corrected.
- Additional failing regressions reproduced duplicate-folder no-op undo and viewport updates rotating backups. Both were corrected.
- 26 automated tests pass in debug and release configurations, including a real temporary Git worktree and native scroll host.
- Desktop and data workers stopped due to workspace spend cap; the primary agent completed integration and inspected the changes. Independent review remains unavailable for the same reason.
- Elevated app-bundle packaging was not executed: automatic approval review could not complete because the workspace spend cap was reached. Do not retry or bypass without resolving this limit or user guidance.
- Live desktop/hotkey, monitor switching, and external-editor launch acceptance remain manual checks; tests do not launch the user's editors or modify their real canvas.

## Completion after quota recovery

- Independent review identified a pending viewport update lost on immediate group teardown. Added a group-specific commit callback and a regression that failed before the fix and passes after it. Scoped re-review found no remaining actionable regression.
- Final release verification: 27 tests, zero failures.
- Rebuilt `build/ProjectCanvas.app` with the reviewed fix; ad-hoc code signature verified.
- UI automation limitation: app inventory reports the running bundle `local.projectcanvas.desktop`, but binding by bundle ID returns `Invalid app`; binding by name or full app path resolves the obsolete `local.projectcanvas.app` and returns `Running application not found`, including after resetting the automation session. Live interaction testing cannot be claimed. Native scroll-host tests pass.

## Desktop connections and blur follow-up

- Added directed, labeled desktop connections sharing the card layout transform and visibility setting; reciprocal edges use separate curves.
- Removed active-app suppression of the blur panel. Native tests verify visible full-screen blur and connection views with mouse click-through.
- Clarified the app shortcut as Cmd-Shift-Space; Fn-F11 retains native macOS behavior.
- Scoped independent review found no blocking issues; corrected its minor extreme-layout scaling finding and added coverage.
- Release suite: 31 tests pass. Rebuilt the app bundle. Perceived blur and live shortcut interaction remain unverified because of the UI automation binding limitation above.
