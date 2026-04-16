# Maxcraft — Cogworks UI migration plan

Maxcraft has the cleanest starting point — its `UI/Shared.lua` was explicitly adapted from Tempo's and is almost identical to the Cogworks UI module. Migration is nearly mechanical.

## Prerequisites

- Maxcraft's `.pkgmeta` already has the Cogworks-1.0 external (done)
- Maxcraft's `.toc` already loads `Libs\Cogworks-1.0\Cogworks-1.0.lua` (done)
- Bump the Cogworks tag in `.pkgmeta` to the version that includes the UI module

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

## What stays in Maxcraft

- `UI.STATUS_COLORS` — domain-specific (satisfied/partial/missing/inactive)
- `UI:StatusColor()`, `UI:StatusHex()` — use Maxcraft's own status enum
- `UI/CoachWidget.lua` — floating step checklist, unique to professions
- `UI/CraftCoach.lua`, `UI/GatherCoach.lua` — domain-specific pages
- `UI/StepEditorPage.lua` — profession step editing
- `UI/Toast.lua` — simple toast, could migrate later but low priority
- All slash commands (`/maxcraft`, `/mxc`)
- `MaxcraftDB` / `MaxcraftCharDB` saved variables

## After migration: what's left in `UI/Shared.lua`

Only domain-specific code:

```lua
local cw = LibStub("Cogworks-1.0")

UI.STATUS_COLORS = { ... }

function UI:StatusColor(status) ... end
function UI:StatusHex(status) ... end
```

About 15 lines, down from 169.

## Estimated scope

- ~15 theme reference replacements across 9 files (Phase 1)
- ~8 factory call replacements (Phase 2)
- ~2 nav button replacements (Phase 3)
- ~120 lines deleted from `UI/Shared.lua`
- Net lines removed: ~130-150
