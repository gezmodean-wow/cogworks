# Maxcraft — Cogworks UI migration plan

Maxcraft has the cleanest starting point — its `UI/Shared.lua` was explicitly adapted from Tempo's and is almost identical to the Cogworks UI module. Migration is nearly mechanical.

The Cogworks library now covers Phase A, B, and C of the buildout (cogworks issue #1) — beyond the original theme/widget migration plan, Maxcraft can also rebuild its CoachWidget heads-up onto `CreateMiniView`, its step editor settings onto `CreateTabPanel` + Forms helpers, and any hierarchical builds onto `CreateTree`. See `flipqueue.md` for the full primitive surface.

## Prerequisites

- Maxcraft's `.pkgmeta` already has the Cogworks-1.0 external (done).
- Maxcraft's `.toc` should load `Libs\Cogworks-1.0\Cogworks-1.0.xml` (the XML manifest pulls in all module files; the old single-`.lua` line predates Forms / TabPanel / MiniView / Wizard / Tree / ReorderableList / Text and won't pick those up).
- Bump the Cogworks tag in `.pkgmeta` once the next tagged Cogworks release ships (likely `v0.11.0`) so the packaged build picks up the full Phase B + C set.

## Phase 1: Theme + backdrop migration

### Step 1: Add Cogworks reference

At the top of `UI/Shared.lua`:

```lua
local cw = LibStub("Cogworks-1.0")
```

### Step 2: Replace `UI.THEME` references

Same mapping as Tempo (Maxcraft's theme table is identical):

| Maxcraft `UI.THEME.*` | Cogworks `cw.Theme.*` |
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

### Files that reference `UI.THEME`

- `UI/Shared.lua` (definition + usage)
- `UI/MainFrame.lua`
- `UI/CoachWidget.lua`
- `UI/CraftCoach.lua`
- `UI/GatherCoach.lua`
- `UI/SettingsPage.lua`
- `UI/StepEditorPage.lua`
- `UI/BuildsPage.lua`
- `UI/Toast.lua`

### Step 3: Replace `UI.BACKDROP` / `UI.BACKDROP_SMALL`

Same as Tempo: `UI.BACKDROP` → `cw.Backdrop`, `UI.BACKDROP_SMALL` → `cw.BackdropSmall`.

### Step 4: Delete from `UI/Shared.lua`

Remove theme and backdrop definitions (lines 24-49).

## Phase 2: Widget factory migration

Maxcraft's `UI/Shared.lua` defines these exact factories:

| Maxcraft function | Cogworks replacement |
|---|---|
| `UI:CreateButton(parent, label, w, h, onClick)` | `cw:CreateButton(...)` |
| `UI:CreateCheckbox(parent, label, desc, init, onChange)` | `cw:CreateCheckbox(...)` |
| `UI:CreateSectionHeader(parent, text, yOffset)` | `cw:CreateSectionHeader(...)` |
| `UI:CreateIconButton(parent, icon, size, tooltip, onClick)` | `cw:CreateIconButton(...)` |

Signatures are identical. Find-and-replace `UI:Create` → `cw:Create`.

### Files that call these factories

- `UI/SettingsPage.lua` — checkboxes, section headers
- `UI/MainFrame.lua` — nav buttons, buttons
- `UI/CoachWidget.lua` — icon buttons
- `UI/StepEditorPage.lua` — buttons, checkboxes

### Delete from `UI/Shared.lua`

Remove factory definitions (lines 68-168). 

## Phase 3: Nav button migration

Maxcraft's `UI/MainFrame.lua` has `createNavButton` and `setActiveButton` (lines 28-76). Replace with:

```lua
local btn = cw:CreateNavButton(sidebar, { label = "Coach", icon = iconPath }, function()
  showPage("coach")
end)
cw:SetNavButtonActive(btn, true)
```

## Phase 4: CoachWidget → MiniView

`UI/CoachWidget.lua` is a floating heads-up step checklist — exactly the shape `cw:CreateMiniView` is for. Drag/resize/persistence chrome moves to the lib; Maxcraft-specific content (current step, progress, ingredient list) lives inside `mini.content`. Persist position/size/pinned via `MaxcraftCharDB.coachWidget`.

`UI/CraftCoach.lua` and `UI/GatherCoach.lua` keep their domain logic but render through the same shared MiniView shell.

## Phase 5: Settings + step editor

`UI/SettingsPage.lua` migrates onto `cw:CreateTabPanel` for any general / advanced splits, `cw:CreateCollapsibleSection` for grouped settings, and `cw:CreateSettingsCheckbox / Button / Input` for the actual rows.

`UI/StepEditorPage.lua` migrates onto Forms helpers (label + input rows) for step parameters. If profession steps form a hierarchy (e.g. recipe → reagent → optional reagents), `cw:CreateTree` covers that shape.

## Phase 6: Builds page

If `UI/BuildsPage.lua` lists builds with sub-steps, `cw:CreateTree` is the natural fit. If it's flat, `cw:CreateScrollTable` covers it.

## Phase 7: Rich-text helpers

Maxcraft uses class-colored character names + quality-colored item names + gold formatting in several places. Replace inline string-formatting with `cw:QualityColorName(name, quality)`, `cw:ClassColorName(name, class)`, `cw:FormatGoldValue(gold)`.

## What stays in Maxcraft

- `UI.STATUS_COLORS` — domain-specific (satisfied/partial/missing/inactive).
- `UI:StatusColor()`, `UI:StatusHex()` — use Maxcraft's own status enum.
- All page *content* (the actual coach data, recipe info, ingredient lists). The shared *chrome* migrates; the domain logic stays.
- `UI/Toast.lua` — could migrate later if Cogworks grows a generic toast primitive (none today).
- All slash commands (`/maxcraft`, `/mxc`).
- `MaxcraftDB` / `MaxcraftCharDB` saved variables.

## After migration: what's left in `UI/Shared.lua`

Only domain-specific code:

```lua
local cw = LibStub("Cogworks-1.0")

UI.STATUS_COLORS = { ... }

function UI:StatusColor(status) ... end
function UI:StatusHex(status) ... end
```

About 15 lines, down from 169.

## Estimated scope (revised)

| Phase                                  | Lines removed (approx) |
|----------------------------------------|------------------------|
| Theme + backdrop migration (Phase 1)   | ~15                    |
| Widget factory migration (Phase 2)     | ~80                    |
| Nav button migration (Phase 3)         | ~50                    |
| CoachWidget → MiniView (Phase 4)       | ~150                   |
| Settings + step editor (Phase 5)       | ~120                   |
| Builds page (Phase 6)                  | ~80                    |
| Rich-text helpers (Phase 7)            | ~30                    |
| **Total**                              | **~500 – 600**         |
