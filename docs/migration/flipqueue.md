# FlipQueue — Cogworks UI migration plan

This plan lets the FlipQueue agent migrate from hardcoded theme values and inline widget creation to the shared Cogworks-1.0 UI primitives. FlipQueue is the biggest win because it has **zero shared theme table** — every color is hardcoded inline across 10+ UI files.

## Status update — primitives now available (2026-04-28, Cogworks v0.10.0 + MINOR 13 in flight)

The Cogworks library has grown well beyond what Phases 1–3 of this doc target. Newly available primitives the FlipQueue migration should use:

- **`cw:CreateScrollTable(parent, columns)`** — shipped, with column sortable/resizable/format, per-row `_rowColor`, `_icon`, `_tooltipText`, `_tooltipExtra`. Replace FlipQueue's local `UI/ScrollTable.lua` entirely (it was previously listed as "stays in FlipQueue"; that's now stale).
- **`cw:CreateCollapsibleSection(parent, opts)`** (`Cogworks-1.0/Sections.lua`) — clickable header + body; persists collapsed state if the caller wires it up. Use anywhere FlipQueue currently rolls its own expand/collapse chrome.
- **`cw:CreateSettingsCheckbox / Button / Input`** (`Cogworks-1.0/Forms.lua`) — labeled-row variants of the base primitives, returning `(row, consumedHeight)` for y-cursor stacking. **Prefer these over naked `cw:CreateCheckbox` / `cw:CreateButton` for settings-page rows** — they handle label/control/description layout, font-scale reflow, and the `onHeightChanged` reflow hook for free.
- **`cw:CreateDropdown(parent, items, selected, onChange, opts)`** — additive 5th arg; pass `{ autoWidth = true, minWidth = 120, maxWidth = 360 }` to fit the widest item label. Re-fits on font-scale change.
- **`cw:CreateCollapsibleSection`** descriptions, summary text, and chevron arrow all use the suite-wide icon registry (`cw:RegisterIcon` / `cw:ApplyIcon`) — registers `chevron-right` / `chevron-down` against friendslist atlases so `▶ ▼` boxes don't appear.
- **`cw:CreatePopup(opts)`** + **`cw:ShowConfirmDialog(...)`** — for the existing FlipQueue confirm/cancel patterns.
- **`cw:RegisterCogMinimapButton(addonName, dataobject, savedvars)`** — shared LDB minimap-button registration with the suite gear-border chrome. Consumer cogs (FlipQueue included) should switch to this in place of any local LibDBIcon wiring; bump the Cogworks `.pkgmeta` tag to `v0.10.0` first.

The phased plan below stays valid as the *theme + base widget* migration. Treat the new primitives above as additional phases the FlipQueue agent can sequence in once the base migration is underway. The estimated scope at the bottom of this doc undercounts — net lines removed will be substantially higher when ScrollTable, Sections, and Forms migrations are factored in.

## Prerequisites

- FlipQueue already embeds Cogworks-1.0 via `.pkgmeta` (done)
- FlipQueue's `.toc` already loads `Libs\Cogworks-1.0\Cogworks-1.0.lua` (done)
- Bump the Cogworks tag in FlipQueue's `.pkgmeta` from `v0.1.0` to the tag that includes the UI module

## Phase 1: Theme constants (highest impact, lowest risk)

FlipQueue hardcodes `{0.08, 0.08, 0.12, 0.95}` and similar values in 10+ files. Replace all of them with `cw.Theme.*` references.

### Step 1: Add a Cogworks reference at the top of `UI/Shared.lua`

```lua
local cw = LibStub("Cogworks-1.0")
```

### Step 2: Replace hardcoded colors across all UI files

Each file that creates frames should get `local cw = LibStub("Cogworks-1.0")` at the top (or receive it via `ns.cw`), then replace:

| Hardcoded value | Replace with |
|---|---|
| `{0.08, 0.08, 0.12, 0.95}` | `cw.Theme.bg` |
| `{0.15, 0.15, 0.2, 1}` | `cw.Theme.header` |
| `{0.06, 0.06, 0.10, 1}` | `cw.Theme.sidebar` |
| `{0.3, 0.3, 0.4, 1}` | `cw.Theme.border` |
| `{1, 0.82, 0, 1}` | `cw.Theme.gold` |
| `{1, 1, 1, 0.03}` | `cw.Theme.rowAlt` |
| `{1, 1, 1, 0.08}` | `cw.Theme.rowHover` |

### Files to touch (grep for `0.08, 0.08, 0.12`)

- `UI/MainFrame.lua`
- `UI/GuildsPage.lua`
- `UI/GeneratorPage.lua`
- `UI/TransformPage.lua`
- `UI/ExportPopup.lua`
- `UI/TSMFrame.lua`
- `UI/TodoPage.lua`
- `UI/UntrackedSection.lua`
- `UI/BankPopup.lua`
- `UI/SetupWizard.lua`
- `UI/SettingsFrame.lua`
- `UI/MiniView.lua`

### Step 3: Replace inline backdrop definitions

FlipQueue's `SetupWizard.lua` defines local `CARD_BACKDROP` and `BTN_BACKDROP`. Replace with `cw.Backdrop` and `cw.BackdropSmall`.

## Phase 2: Widget factories (medium impact)

FlipQueue creates buttons, checkboxes, and icon buttons inline in many files. Replace with Cogworks factories.

### Buttons

Search for `CreateFrame("Button"` followed by `SetBackdrop` / `SetBackdropColor` / hover scripts. Replace the entire pattern with:

```lua
local btn = cw:CreateButton(parent, "Label", 100, 24, function() ... end)
```

### Checkboxes

`UI/SettingsFrame.lua` creates checkboxes inline (lines ~115-150). Replace with:

```lua
local cb = cw:CreateCheckbox(parent, "Label", "Description", initialValue, onChange)
```

### Icon buttons

`UI/MiniView.lua` has a local `createIconButton` function (lines ~79-99). Replace calls with:

```lua
local btn = cw:CreateIconButton(parent, icon, size, tooltip, onClick)
```

## Phase 3: Quality colors consolidation

FlipQueue defines `QUALITY_COLORS` and `QUALITY_NUM_COLORS` in `UI/Shared.lua`. These overlap with `cw.Theme.quality`. Migrate:

```lua
-- Before
local color = QUALITY_NUM_COLORS[quality]
-- After
local qc = cw.Theme.quality[quality]
local color = qc and string.format("%02x%02x%02x", qc[1]*255, qc[2]*255, qc[3]*255)
```

## What stays in FlipQueue

- `UI/BankPopup.lua`, `UI/ExportPopup.lua` — transaction-specific UI
- `UI/SetupWizard.lua` — onboarding flow unique to FlipQueue
- `UI/GeneratorPage.lua` — queue generation UI
- All domain-specific status colors (auction statuses)
- All slash commands (`/fq`, `/flipqueue`)
- `FlipQueueDB` saved variables

## Estimated scope

- ~30 hardcoded color replacements across 12 files (Phase 1)
- ~8-12 widget factory replacements (Phase 2)
- ~1 quality color migration (Phase 3)
- Net lines removed: ~80-120
