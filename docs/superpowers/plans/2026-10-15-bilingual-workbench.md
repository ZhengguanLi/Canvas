# Bilingual Workbench Implementation Plan

> For agentic workers: use subagent-driven-development for scoped implementation and review.

**Goal:** Deliver approved bilingual UX, discovery, organization, metadata, safe layouts and desktop appearance.
**Architecture:** Extend Codable records compatibly; keep mutations/undo in AppModel. Isolate pure search/layout logic. Preview owns copied data, and only explicit Apply commits. Localize after feature UI stabilizes.
**Tech Stack:** Swift 5.10, SwiftUI/AppKit, XCTest.
**Spec:** ../specs/2026-10-15-bilingual-workbench.md

## Global constraints
- macOS 14+, no dependencies, preserve user data and native Fn-F11.
- No commits of pre-existing untracked sources. Backup exists in /private/tmp/ProjectCanvas-before-bilingual-sources.

## Tasks
- [x] 1. Models, search, regions, details, safe layout: modify Models/AppModel/CanvasStorage/MainWindow/CanvasBoard; create focused views and pure layout helpers. Tests cover legacy decode, import membership remap, notes/links undo, search results and cycles. Assert preview generation leaves disk bytes and positions untouched; Apply/undo restores exact coordinates; stale proposals cannot overwrite edits.
- [x] 2. Desktop appearance: DesktopAppearance preferences, PreferencesView controls, DesktopDisplay and DesktopSceneLayout integration. Clamp inputs, keep edges aligned and label visibility independent. Test defaults/persistence/clamping/scaling.
- [x] 3. Localization: central language preference and resource lookup; translate all application strings, including dynamic errors. Refresh SwiftUI root and AppKit panels without resetting workspace state. Test coverage, fallback and persistence.
- [x] 4. Review all feature changes for data preservation and layout safety; fix findings. Run full release tests, package and verify signature. Update README with controls and limitations.

## Ledger
- Plan authorized by user selection of features 1–4 and 6 plus language. No further feature selection needed.
- Task 1 owns Models/AppModel/CanvasStorage/MainWindow/CanvasBoard and new feature views; task 2 owns desktop files and PreferencesView. Task 3 is sequential after both to avoid competing text edits.
- Shared interfaces: desktop uses existing group.cards/connections; optional regions/notes must preserve those. Task 2 must not edit AppModel. Task 3 wraps user-visible text without changing persisted raw values.
- Each task agrees with legacy-data and no-commit constraints. Tests use isolated preferences and temporary files.

## Verification and follow-up

- Release suite: 43 tests passed, zero failures, native window test included.
- Independent reviews covered model/storage, desktop appearance, localization/UI, region header correction, and background dismissal; no unresolved findings.
- User follow-up: clicking the frosted background outside cards dismisses the desktop display. Regression reproduced four failures before implementation and passed afterward.
- UI automation cannot bind the app in this environment; actual keyboard/mouse and compositor appearance have not been manually verified.
