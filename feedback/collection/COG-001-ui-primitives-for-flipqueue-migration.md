---
id: COG-001
cog: cogworks
status: in-progress
title: UI primitive buildout for FlipQueue migration
sources:
  - type: internal
    session: 2026-04-21
    note: Roadmap captured after gap analysis of Cogworks vs FlipQueue UI surfaces
reporters: []
created: 2026-04-21
updated: 2026-04-21
release: null
tags: [ui, primitives, migration, flipqueue, roadmap]
---

## Summary

Accumulate the UI primitives FlipQueue needs so it can migrate off its locally-built widgets (ScrollTable, Dropdown, Tree, Alloc list, settings form helpers, collapsible sections) onto Cogworks equivalents. Phased buildout — foundational primitives first, specialized primitives later.

Outcome: FlipQueue UI shrinks ~3–4k LOC via dedup, gains consistent theme/font/scale behavior via Cogworks, and all future cogs (Tempo, Maxcraft, Tally, planned ledger) get the same toolkit for free.

## Reproduction

Motivation (from 2026-04-21 gap analysis):

- **Cogworks already has**: theme, settings kernel, fonts, event bus, Button / IconButton / Checkbox / ProgressBar / SectionHeader / NavButton, basic Dropdown, basic ScrollTable, Popup, ConfirmDialog, PlayAlert, PrintPrefix, backdrops, GearAssembly.
- **FlipQueue has** rich page-level UI built on local widgets (28 page/component files) plus native WoW templates (BasicFrameTemplateWithInset, InputBoxTemplate, etc.).
- **Gap**: ~8 missing primitives and 3 partial primitives need work before migration is straightforward.

## Attempts

- **2026-04-21**: Roadmap captured from gap analysis. No primitives built yet under this initiative.

## Notes

### Phase A — foundational (unblocks most FlipQueue pages)

1. **Settings form helpers bundle**: `CreateSettingsCheckbox`, `CreateSettingsButton`, `CreateSettingsInput` (numeric + text), expanded `CreateDropdown` (auto-width + scroll when items > N). Each returns row frame + consumed height for auto-layout.
2. **CreateCollapsibleSection**: title + summary + expand/collapse arrow. Persists `collapsed[key]` under caller's settings dict. Returns section frame + content frame.
3. **ScrollTable enhancements**: per-row background color, custom cell renderer (inline icons, quality-colored text). Eliminates FlipQueue's `UI/ScrollTable.lua` as redundant.
4. **CreateDropdown enhancements**: auto-width based on items; scroll frame when items exceed threshold. Migration-safe addition to existing `CreateDropdown`.

### Phase B — page-specific pre-reqs + new additions

5. **CreateTabPanel**: inline horizontal tabs (distinct from sidebar `CreateNavButton`). Content switcher with `SetActiveTab(key)`. Used by ExportPopup-like multi-form flows and ResearchPage.
6. **Tooltip / rich-text helpers**: hoist `UI/Shared.lua` utilities (`QualityColorName`, `LookupItemInfo`, `FormatGoldValue`, class colors) into Cogworks as suite-wide UI utilities.
7. **CreateMiniView**: draggable / pinnable / scale-aware heads-up frame for per-cog mini displays. Standard chrome (title bar, close, pin, resize grip). Position/scale persisted per cog. Consumers: FlipQueue (existing mini view), Tempo (reset timer), Tally (running total), Maxcraft (profession progress).
8. **CreateWizard**: multi-step flow widget. `SetSteps(stepDefs)`, `Next()`, `Previous()`, `OnComplete(fn)`, progress indicator, per-step validation gate. Consumers: onboarding, import flows, config migrators, future in-game equivalents of `/cog-init`.

### Phase C — specialized (defer; scope by demand)

9. **CreateTree**: hierarchical expand/collapse with item counts. Used only by FlipQueue's ResearchPage. Before building, evaluate whether a flat filtered-list UX is acceptable — could skip ~500 LOC.
10. **CreateReorderableList**: row-pool + drag-drop + swap/insert callback. Used only by FlipQueue's AllocWidget. Defer until confirmed needed.

### Tempo / task domain — intentionally NOT in scope

Cogworks will NOT ship a generic task/todo widget. Tempo will eventually own the "task with cadence + completion state" public API. FlipQueue's TodoList migrates to Tempo (not Cogworks) when Tempo's model stabilizes. Avoids baking FlipQueue-specific assumptions into a library layer that turns out to be wrong once Tempo's model becomes canonical.

### Font-scaling discipline (non-negotiable for every new widget)

Every widget in this initiative MUST:
- Pull font objects from `lib:GetFont(key)` — never hard-code `GameFontNormal` etc.
- Subscribe to `SettingsChanged` on `fontScale` / `fontFamily` / `uiScale` and reapply in-place.
- Recalculate consumed-height / layout on font change.
- Verify at 0.7x and 1.5x scales: no clipping, no overflow, no collision.

Fold this requirement into cogworks CLAUDE.md before the first primitive lands so it's on the review bar from day one.

### Cross-initiative dependencies

- **COG-002** (cross-realm service) — not blocking, but settings form helpers and ScrollTable primitives will be consumers. Both can proceed in parallel.
- **COG-003** (minimap gear-border) — independent.

## Next steps

1. **Phase A starter**: build `CreateCollapsibleSection` first — simplest, highest leverage, exercises the SettingsChanged subscribe + consumed-height API shape that the other Phase A items reuse.
2. **Migration tracking**: once Phase A primitives land in Cogworks MINORs, log each FlipQueue page migration as an Attempts entry on this issue (or split out a FQ-XXX migration sub-issue if scope grows).
3. **Re-evaluate Phase C** (tree + reorderable list) after Phase A/B complete — may find the UX can be reshaped to avoid the primitive entirely.
4. **Deletion pass** in FlipQueue once everything lands: remove `UI/ScrollTable.lua`, local dropdown code, local collapsible code, local settings form helpers. Tag as a FlipQueue major version bump.
