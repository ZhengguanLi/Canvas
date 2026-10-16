# Desktop drag and Escape

Approved follow-up: desktop cards can be dragged, corresponding canvas coordinates save on release; Escape cancels an active drag, then dismisses the desktop when idle.

- [x] Add inverse desktop geometry and stable session transform; dragging must not recenter the scene or save per mouse movement.
- [x] Distinguish click from drag; preview card/edges and commit one undoable move. Cancel safely when group/display changes.
- [x] Register Escape only during desktop presentation, unregister on hide; preserve Cmd-Shift-Space and native Fn-F11.
- [x] Regression tests for scaling, offset displays, persistence, undo, cancel, dismiss and accidental-open prevention.
- [ ] Independent review, release tests, app rebuild and signature verification.

Do not commit pre-existing untracked source. Tests use temporary storage/preferences. Live user-interface interaction remains subject to the existing automation binding limitation.

## Verification

- New missing-API tests failed before implementation. Final constrained suite: 47 tests, 45 passed, 2 native-window tests skipped, zero failures.
- Release executable built in the restricted environment; existing app bundle updated and ad-hoc signature verified. Executable UUID matches bundled binary.
- Native elevated test command was rejected by automatic approval review because the workspace spend cap prevented review completion. It was not executed. No native-window bypass attempted; actual desktop drag and Escape acceptance remain unverified.
- Delegated implementation stopped at the same spend cap after writing initial geometry tests; primary agent completed implementation and source review. Independent review remains unavailable.
