# Bilingual workbench

Approved scope: language switching; global search; named colored regions; project notes and links; relationship layout previews; desktop appearance.

- Language: system, Simplified Chinese, English; persisted and applied to SwiftUI and AppKit immediately. Translate application copy, not user-authored names, notes or labels.
- Search: Cmd-K searches every group's project name/path; keyboard selection, open, and locate on canvas.
- Regions: create from selected cards, name/color, move members together; remove a region without deleting cards. Persist and export/import with remapped memberships.
- Details: project-level notes and named HTTP(S) links, shared across groups, editable with cancel/save and undo.
- Layout: deterministic directed layer layout with cycle handling. Preview is a separate read-only canvas; never mutate saved positions before Apply. Cancel/close leave storage and undo unchanged. Apply is one undoable operation, rejects stale previews. Existing grid layout also goes through preview.
- Desktop: persistent blur appearance, dimming, card scale and connection-label visibility. Changes refresh open desktop windows. Fn-F11 remains untouched.
- macOS 14+, SwiftUI/AppKit, no new dependencies. Preserve legacy data; tests use temporary storage. Existing untracked source must not be committed wholesale.

User approved these features and explicitly requires protecting hand-adjusted layouts. Preview is the chosen reversible implementation detail within that authorization.
