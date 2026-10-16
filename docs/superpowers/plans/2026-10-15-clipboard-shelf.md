# Main-window clipboard shelf

User approved two independently scrolling image/text sections with counts, recopy, delete and clear; explicitly main window only.

- [x] Add bounded in-memory clipboard history, excluding private/transient/generated/file clipboard payloads, deduplication, pause and clear. Capture new copies while app runs; do not import CopyHang files or existing clipboard on startup.
- [x] Validate image dimensions and bytes before thumbnail decoding; process images away from main thread. Avoid replaying the app's own clipboard writes.
- [x] Add two horizontal scrolling rows above project workspace; counts, previews, recopy, per-item removal and per-category clear, pause/resume and collapse. Localize all application copy.
- [x] Test history, limits, privacy exclusions, dual-format classification, image validation, clear and deduplication with synthetic data (never user clipboard).
- [x] Run available tests and release build, update signed local app and documentation. Keep native interaction limits explicit.

History lasts for the current app session and is not saved to disk. Each section retains up to 50 items, with memory limits. This keeps the initial implementation focused on the requested quick-access surface.

## Verification

- Five clipboard tests cover classification, exclusion markers, pause, empty/oversize payloads, deduplication, ordering/limits, real image thumbnail decoding and independent clear behavior. Tests use synthetic data, never the user clipboard.
- Final release suite: 52 tests, 50 passed, 2 native-window tests skipped by restricted environment, zero failures.
- Updated local app executable and verified ad-hoc signature and matching executable UUID. Live clipboard capture and pointer scrolling were not manually exercised; the existing native automation/approval limitation remains.

## Placement correction

User corrected the target to the foreground desktop overlay, replacing the earlier main-window-only choice. Removed the main-window shelf; added a nonactivating interactive panel at the selected screen top, integrated close control, and reserved card/drag space below it. Collapse updates that reserved area; empty groups still show the clipboard. Background mode does not display the shelf. Tests cover offset-screen geometry and native panel separation/hiding (native test requires window access).
