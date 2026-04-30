# Tempo — Cogworks UI migration plan

Tempo already has a clean `UI/Shared.lua` with a shared `UI.THEME` table and widget factories. Migration is straightforward: replace the local definitions with calls to Cogworks-1.0, then delete the duplicated code.

The Cogworks library now covers Phase A, B, and C of the buildout (cogworks issue #1) — beyond the original theme/widget migration plan, Tempo can also rebuild its mini view, setup wizard, tabbed settings, and task hierarchies on shared primitives. See `flipqueue.md` for the full primitive surface (`CreateTabPanel`, `CreateMiniView`, `CreateWizard`, `CreateTree`, `CreateReorderableList`, settings form helpers, rich-text helpers).

## Prerequisites

- Tempo's `.pkgmeta` already has the Cogworks-1.0 external (done).
- Tempo's `.toc` should load `Libs\Cogworks-1.0\Cogworks-1.0.xml` (the XML manifest pulls in all module files; the old single-`.lua` line predates Forms / TabPanel / MiniView / Wizard / Tree / ReorderableList / Text and won't pick those up).
- Bump the Cogworks tag in `.pkgmeta` once the next tagged Cogworks release ships (likely `v0.11.0`) so the packaged build picks up the full Phase B + C set.

## Phase 1: Theme table migration

### Step 1: Add Cogworks reference

At the top of `UI/Shared.lua`:

```lua
local cw = LibStub("Cogworks-1.0")
```

### Step 2: Replace `UI.THEME` with `cw.Theme`

Tempo's `UI.THEME` keys map to Cogworks `lib.Theme` as follows:

| Tempo `UI.THEME.*` | Cogworks `cw.Theme.*` |
|---|---|
| `BG` | `bg` |
| `BORDER` | `border` |
| `HEADER_BG` | `header` |
| `SIDEBAR_BG` | `sidebar` |
| `ROW_ALT` | `rowAlt` |
| `ROW_HOVER` | `rowHover` |
| `ACCENT` | `gold` |
| `TEXT_NORMAL` | `text` |
| `TEXT_DIM` | `textDim` |
| `TEXT_DISABLED` | `textDisabled` |

### Step 3: Find-and-replace across all UI files

Every reference to `UI.THEME.X` becomes `cw.Theme.x` (or store `local T = cw.Theme` at file top).

Files that reference `UI.THEME`:
- `UI/Shared.lua` (definition + usage)
- `UI/MainFrame.lua`
- `UI/ScrollTable.lua`
- `UI/DashboardPage.lua`
- `UI/TaskListPage.lua`
- `UI/AllCharactersPage.lua`
- `UI/TaskEditorPage.lua`
- `UI/SettingsPage.lua`
- `UI/MiniView.lua`
- `UI/Toast.lua`
- `UI/SetupWizard.lua`

### Step 4: Replace `UI.BACKDROP` and `UI.BACKDROP_SMALL`

```lua
-- Before
btn:SetBackdrop(UI.BACKDROP_SMALL)
-- After
btn:SetBackdrop(cw.BackdropSmall)
```

### Step 5: Delete from `UI/Shared.lua`

Remove the `UI.THEME`, `UI.BACKDROP`, and `UI.BACKDROP_SMALL` definitions (lines 38-67). These now live in Cogworks.

## Phase 2: Widget factory migration

Tempo's `UI/Shared.lua` defines these factories that are now in Cogworks:

| Tempo function | Cogworks replacement |
|---|---|
| `UI:CreateButton(parent, label, w, h, onClick)` | `cw:CreateButton(parent, label, w, h, onClick)` |
| `UI:CreateCheckbox(parent, label, desc, init, onChange)` | `cw:CreateCheckbox(parent, label, desc, init, onChange)` |
| `UI:CreateSectionHeader(parent, text, yOffset)` | `cw:CreateSectionHeader(parent, text, yOffset)` |
| `UI:CreateProgressBar(parent, w, h)` | `cw:CreateProgressBar(parent, w, h)` |

Signatures are identical — this is a straight find-and-replace of `UI:Create` → `cw:Create` in the calling code.

### Files that call these factories

- `UI/SettingsPage.lua` — checkboxes, section headers
- `UI/MainFrame.lua` — nav buttons (if migrated), buttons
- `UI/TaskEditorPage.lua` — buttons, checkboxes
- `UI/DashboardPage.lua` — progress bars
- `UI/MiniView.lua` — icon buttons (local function → `cw:CreateIconButton`)

### Step: Delete from `UI/Shared.lua`

Remove the factory function definitions (lines 131-293). These now live in Cogworks.

## Phase 3: Nav button migration

Tempo's `UI/MainFrame.lua` has `CreateNavButton` and `SetNavButtonActive` (lines 94-159). Replace with:

```lua
local btn = cw:CreateNavButton(sidebar, { label = "Dashboard", icon = iconPath }, function()
  self:ShowPage("dashboard")
end)
cw:SetNavButtonActive(btn, true)
```

## Phase 4: ScrollTable migration

`cw:CreateScrollTable(parent, columns)` now covers what Tempo's `UI/ScrollTable.lua` does, with extra goodies (per-row `_rowColor`, `_icon`, `_tooltipText`, `_tooltipExtra`). Migrate every consumer:

- `UI/DashboardPage.lua` — task summary table.
- `UI/TaskListPage.lua` — task list table.
- `UI/AllCharactersPage.lua` — per-character roll-up table.

Once these migrate, `UI/ScrollTable.lua` deletes.

## Phase 5: MiniView migration

`UI/MiniView.lua` rebuilds onto `cw:CreateMiniView`. The local drag/resize/persistence logic deletes; Tempo-specific content (next reset countdown, character status pills, etc.) lives inside `mini.content`. Position/size/pinned state persists via Tempo's `TempoCharDB.miniView` table.

The reset-timer heads-up that has been on the roadmap for Tempo specifically lands here — same primitive, different content.

## Phase 6: Wizard migration

`UI/SetupWizard.lua` rebuilds onto `cw:CreateWizard`. Each onboarding step becomes a `{ key, title, build, validate }` entry. The wizard owns Cancel / Previous / Next / Finish; Tempo's onboarding logic lives in the per-step `build` functions.

## Phase 7: Settings page rewrite

`UI/SettingsPage.lua` migrates onto:
- `cw:CreateTabPanel` for general / per-character / advanced splits.
- `cw:CreateCollapsibleSection` for grouped settings within a tab.
- `cw:CreateSettingsCheckbox / Button / Input` for the actual rows (replace any naked `cw:CreateCheckbox` calls in settings rows with the labeled-row variants — they handle the layout automatically).

## Phase 8: Cross-realm helpers

Tempo's reset-timing logic depends on knowing realm-local cutoffs. `cw:NormalizeRealmKey`, `cw:RealmMatches`, `cw:RealmsOverlap` (`Cogworks-1.0/Realms.lua`) handle the normalization piece today. Server-time / connected-realm group helpers are still pending in cogworks issue #2 — Tempo can adopt them when they land without rewiring the rest of the migration.

## What stays in Tempo

- `UI.STATUS_COLORS` — domain-specific (incomplete/in_progress/complete/skipped).
- `UI.PERIOD_COLORS` — domain-specific (daily/weekly/etc.).
- `UI:FormatStatus()` — uses Tempo's own status enum.
- `UI:FormatPeriodHeader()` — uses Tempo's Time module.
- `UI/Toast.lua` — Tempo's pooled toast system is more complex than the generic case (no Cogworks equivalent yet; revisit if Maxcraft / FlipQueue grow similar pools).
- All page-specific *content* (the table data, the period grouping, the task-edit form fields). The shared *chrome* migrates; the domain logic stays.
- All slash commands (`/tempo`, `/tmp`).
- `TempoDB` / `TempoCharDB` saved variables.

## Estimated scope (revised)

| Phase                                  | Lines removed (approx) |
|----------------------------------------|------------------------|
| Theme + backdrop migration (Phase 1)   | ~20                    |
| Widget factory migration (Phase 2)     | ~80                    |
| Nav button migration (Phase 3)         | ~70                    |
| ScrollTable migration (Phase 4)        | ~400 (deletes `UI/ScrollTable.lua`) |
| MiniView migration (Phase 5)           | ~150                   |
| Wizard migration (Phase 6)             | ~100                   |
| Settings page rewrite (Phase 7)        | ~120                   |
| **Total**                              | **~900 – 1,000**       |

Net delta is smaller after the Cogworks calls go in, but Tempo's `UI/Shared.lua` shrinks to ~15-20 lines (status / period colors only) and several whole files delete.
