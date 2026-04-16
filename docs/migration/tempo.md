# Tempo — Cogworks UI migration plan

Tempo already has a clean `UI/Shared.lua` with a shared `UI.THEME` table and widget factories. Migration is straightforward: replace the local definitions with calls to Cogworks-1.0, then delete the duplicated code.

## Prerequisites

- Tempo's `.pkgmeta` already has the Cogworks-1.0 external (done)
- Tempo's `.toc` already loads `Libs\Cogworks-1.0\Cogworks-1.0.lua` (done)
- Bump the Cogworks tag in `.pkgmeta` to the version that includes the UI module

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

## What stays in Tempo

- `UI.STATUS_COLORS` — domain-specific (incomplete/in_progress/complete/skipped)
- `UI.PERIOD_COLORS` — domain-specific (daily/weekly/etc.)
- `UI:FormatStatus()` — uses Tempo's own status enum
- `UI:FormatPeriodHeader()` — uses Tempo's Time module
- `UI/ScrollTable.lua` — too large for generic extraction
- `UI/Toast.lua` — Tempo's pooled toast system is more complex than the generic case
- `UI/SetupWizard.lua` — onboarding unique to Tempo
- All page-specific UI (Dashboard, TaskList, AllCharacters, etc.)
- All slash commands (`/tempo`, `/tmp`)
- `TempoDB` / `TempoCharDB` saved variables

## Estimated scope

- ~20 theme reference replacements across 11 files (Phase 1)
- ~10 factory call replacements (Phase 2)
- ~2 nav button replacements (Phase 3)
- ~160 lines deleted from `UI/Shared.lua`
- Net lines removed: ~160-180
