# FlipQueue — Cogworks UI migration plan

This plan moves FlipQueue from hardcoded theme values + locally-built widgets onto the shared Cogworks-1.0 primitives. The Cogworks library now covers Phase A, B, and C of the buildout (cogworks issue #1) — the entire FlipQueue UI can be rebuilt on top of it.

## Current Cogworks primitive surface (MINOR 15)

What the FlipQueue agent has to work with:

### Foundation
- `cw.Theme` — themed color palette (bg, header, sidebar, border, gold, brass, arcane, success/warning/error, text/textDim/textDisabled, rowAlt/rowHover, quality[N], status, ...). Live theme switching via `cw:SetTheme(name)`.
- `cw.Backdrop` / `cw.BackdropSmall` — themed backdrop tables (16-px / 10-px edge).
- `cw.Fonts.normal / .small / .large / .header` — scaled FontObjects. Pull via `cw:GetFont(key)` so font-scale changes propagate. Subscribe to `cw.Events.SettingsChanged` for `fontScale` / `fontFamily` reflow.
- `cw.RegisterCallback / .UnregisterCallback / cw.Events` — CallbackHandler-1.0 event bus shared across the suite.

### Base widgets (Phase 0 — already shipped, no migration plan needed beyond "use these")
- `cw:CreateButton(parent, label, w, h, onClick)`
- `cw:CreateCheckbox(parent, label, description, value, onChange)`
- `cw:CreateIconButton(parent, icon, size, tooltip, onClick)`
- `cw:CreateSectionHeader(parent, text, yOffset)`
- `cw:CreateProgressBar(parent, w, h)`
- `cw:CreateNavButton(parent, navItem, onClick)` + `cw:SetNavButtonActive(btn, active)` — sidebar nav
- `cw:CreateDropdown(parent, items, selectedKey, onChange, opts?)` — `opts.autoWidth` / `minWidth` / `maxWidth`; menu flips up when there isn't room below
- `cw:CreateScrollTable(parent, columns)` — sortable, resizable, per-row `_rowColor` / `_icon` / `_tooltipText` / `_tooltipExtra`; replaces FlipQueue's local `UI/ScrollTable.lua` entirely
- `cw:CreatePopup(opts)` + `cw:ShowConfirmDialog(title, msg, onYes, onNo)`
- `cw:RegisterCogMinimapButton(addonName, dataobject, savedvars)` — LDB minimap button with the suite gear ring; FlipQueue already adopted this in `UI/MinimapButton.lua`

### Phase A — settings / forms / sections (shipped)
- `cw:CreateCollapsibleSection(parent, opts)` (`Sections.lua`) — header + body with expand/collapse. `opts.contentHeightFn` for wrapping body text; `opts.onLayoutChanged` for sibling reflow. `section.content` is the body frame.
- `cw:CreateSettingsCheckbox(parent, opts)`, `cw:CreateSettingsButton(parent, opts)`, `cw:CreateSettingsInput(parent, opts)` (`Forms.lua`) — labeled-row variants returning `(row, consumedHeight)`. Each takes optional `description`, `onHeightChanged` for stack reflow on font-scale change.

### Phase B — page composition (shipped)
- `cw:CreateTabPanel(parent, opts)` (`TabPanel.lua`) — inline horizontal tabs + content area; tab pages lazy-built; auto-fits label widths. For settings dialogs, multi-form popups, breakdown views.
- `cw:CreateMiniView(opts)` (`MiniView.lua`) — heads-up frame with title bar (title + pin + close), resize grip, content area. Position / size / pinned state persists into a caller-supplied `savedvars` table. Honors `cw.settings.uiScale`.
- `cw:CreateWizard(parent, opts)` (`Wizard.lua`) — multi-step flow with header (title + progress dots), lazy step pages, footer (Cancel / Previous / Next-or-Finish), and per-step `validate()` gates. Caller calls `wizard:Refresh()` to revalidate after user input.
- `cw:QualityColorName(name, quality)`, `cw:QualityColorHex(quality)`, `cw:ClassColor(class)`, `cw:ClassColorName(name, class)`, `cw:FormatGoldValue(gold)`, `cw:FormatGSC(copper)`, `cw:FormatGoldShort(copper)` (`Text.lua`) — rich-text helpers lifted from FlipQueue's `UI/Shared.lua`.

### Phase C — specialized (shipped)
- `cw:CreateTree(parent, opts)` (`Tree.lua`) — hierarchical expand/collapse with chevrons, optional per-node counts, click-to-select. For `ResearchPage`.
- `cw:CreateReorderableList(parent, opts)` (`ReorderableList.lua`) — drag-to-reorder vertical list; caller owns row content via `renderRow(row, item, index)`. For `AllocWidget`.

### Item / realm / API helpers (already shipped)
- `cw:MakeItemKey`, `cw:ParseItemLink`, `cw:ItemKeyToItemString`, `cw:ResolveItemID`, `cw:ItemsMatch` — item-key infra (FlippingPal shape)
- `cw:NormalizeAccents`, `cw:NormalizeRealmKey`, `cw:RealmMatches`, `cw:RealmsOverlap` — realm normalization + matching
- `cw:RegisterAPI`, `cw:GetAPI`, `cw:WhenAPIReady`, `cw:GetRegisteredAPIs` — versioned cross-cog API registry

## Prerequisites

- FlipQueue already embeds Cogworks-1.0 via `.pkgmeta` (done — pinned to a tag).
- FlipQueue's `.toc` loads `Libs\Cogworks-1.0\Cogworks-1.0.xml` (post-v0.10.0 sync — the `.xml` manifest pulls in all module files; the old single-`.lua` line predates Forms / TabPanel / MiniView / Wizard / Tree / ReorderableList / Text / etc.).
- Bump the Cogworks tag in `.pkgmeta` to the next tagged release once Cogworks publishes one with the full Phase B + C set (likely `v0.11.0`). Until then, the local `Libs/Cogworks-1.0/` is sync'd manually for in-game testing.

## Phase 1 — Theme constants (highest impact, lowest risk)

FlipQueue hardcodes `{0.08, 0.08, 0.12, 0.95}` and similar tables across 10+ UI files. Replace with `cw.Theme.*` references.

### Add a Cogworks reference

Each UI file that creates frames should grab Cogworks at the top:

```lua
local cw = LibStub("Cogworks-1.0")
local T  = cw.Theme  -- shorthand, optional
```

### Hardcoded → theme replacements

| Hardcoded value              | Replace with                |
|------------------------------|------------------------------|
| `{0.08, 0.08, 0.12, 0.95}`   | `cw.Theme.bg`                |
| `{0.15, 0.15, 0.2, 1}`       | `cw.Theme.header`            |
| `{0.06, 0.06, 0.10, 1}`      | `cw.Theme.sidebar`           |
| `{0.3, 0.3, 0.4, 1}`         | `cw.Theme.border`            |
| `{1, 0.82, 0, 1}`            | `cw.Theme.gold`              |
| `{1, 1, 1, 0.03}`            | `cw.Theme.rowAlt`            |
| `{1, 1, 1, 0.08}`            | `cw.Theme.rowHover`          |

Inline backdrop tables in `SetupWizard.lua` (`CARD_BACKDROP`, `BTN_BACKDROP`) can be replaced wholesale with `cw.Backdrop` / `cw.BackdropSmall`.

`grep -r "0.08, 0.08, 0.12" UI/` to find them; ~30 occurrences across the file list below.

## Phase 2 — Base widgets

Replace inline `CreateFrame("Button", ...)` + `SetBackdrop` + hover-script clusters with `cw:CreateButton` etc. Pattern repeats for checkboxes (`SettingsFrame.lua` lines ~115-150) and icon buttons (`MiniView.lua` `createIconButton`). Specific:

| Inline pattern                                        | Cogworks call                                                                  |
|-------------------------------------------------------|--------------------------------------------------------------------------------|
| Themed Button + hover scripts                         | `cw:CreateButton(parent, label, w, h, onClick)`                                |
| Themed CheckButton + label                            | `cw:CreateCheckbox(parent, label, desc, value, onChange)`                      |
| Icon-only button with tooltip                         | `cw:CreateIconButton(parent, icon, size, tooltip, onClick)`                    |
| Section header (uppercase divider label)              | `cw:CreateSectionHeader(parent, text, yOffset)`                                |
| Progress bar with text overlay                        | `cw:CreateProgressBar(parent, w, h)` then `:SetProgress(cur, max)`             |
| Sidebar nav button                                    | `cw:CreateNavButton(parent, navItem, onClick)` + `:SetNavButtonActive(b, on)`  |

## Phase 3 — Settings page rewrite (`UI/SettingsFrame.lua`)

This is FlipQueue's biggest single-file win after the ScrollTable migration. Replace:

- Section dividers → `cw:CreateCollapsibleSection(parent, { title, summary, startCollapsed?, onLayoutChanged = function() relayout() end })`. Anchor each section to a y-cursor; on `onLayoutChanged` re-walk the cursor.
- Settings rows → `cw:CreateSettingsCheckbox / Button / Input` returning `(row, consumedHeight)`. Stack via cursor; subscribe to `onHeightChanged` for stack reflow on font-scale change.
- Multi-page settings (general / advanced / debug splits) → `cw:CreateTabPanel(parent, { tabs = { { key, label, build = function(content) ... end }, ... } })`. Each tab page contains its own collapsible sections + form rows.

## Phase 4 — Tables (the big LOC win)

FlipQueue's `UI/ScrollTable.lua` is now redundant — `cw:CreateScrollTable(parent, columns)` covers everything it does plus per-row `_rowColor` / `_icon` / `_tooltipText` / `_tooltipExtra`. Migrate every consumer:

- `UI/CharactersPage.lua` — character list table.
- `UI/InventoryPage.lua` — inventory table.
- `UI/GuildsPage.lua` — guild list table.
- `UI/LogPage.lua` — sales log table.
- `UI/GeneratorPage.lua` — generator output table.
- `UI/TransformPage.lua` — transform results.
- `UI/DealFinderPage.lua` — deal finder results.
- `UI/DealFinderDetail.lua` — detail breakdown.
- `UI/TodoPage.lua` — todo list table.
- `UI/ExportPage.lua` — export preview.
- `UI/DebugPage.lua` — debug rows.

Once these are migrated, `UI/ScrollTable.lua` deletes entirely.

## Phase 5 — Mini views and drawers

`UI/MiniView.lua` becomes a wrapper around `cw:CreateMiniView`. The local drag/resize/persistence logic deletes; the FlipQueue-specific content (count of pending deals, gold icon, etc.) lives inside `mini.content`.

`UI/ContextDrawer.lua` and `UI/ToolDrawer.lua` are the same shape (heads-up panels anchored near the main UI) — both migrate onto `cw:CreateMiniView` with their own savedvars sub-tables.

## Phase 6 — Wizards

`UI/SetupWizard.lua` rebuilds onto `cw:CreateWizard` — define each step as `{ key, title, build = function(content) ... end, validate = function() ... end }`. Onboarding logic moves into the per-step `build` functions. The wizard owns navigation (Previous / Next / Finish / Cancel); FlipQueue owns the validation logic.

`UI/TutorialPage.lua` is a candidate for the same treatment if it's a multi-step flow.

`UI/ImportPage.lua` and `UI/ExportPopup.lua` may also benefit from a wizard-style step-through if they have confirmation flows.

## Phase 7 — Tree (research)

`UI/ResearchPage.lua` rebuilds onto `cw:CreateTree`. FlipQueue's research data is already hierarchical (item categories → items); map it to the tree node shape:

```lua
{ key, label, count?, children? }
```

`tree:SetNodes(nodes)` replaces the whole tree; `tree:Expand(key)` / `:Collapse(key)` for programmatic state; `tree:GetSelected()` for current selection. Click-to-toggle vs click-to-select is split by chevron-zone — works out of the box.

## Phase 8 — Reorderable list (alloc)

`UI/AllocWidget.lua` rebuilds onto `cw:CreateReorderableList`. `renderRow(row, item, index)` populates each row with FlipQueue's existing layout (item icon, name, alloc count, etc.). `onReorder(items, from, to)` updates FlipQueue's internal alloc array.

## Phase 9 — Text helpers consolidation

`UI/Shared.lua` defines `QualityColorName`, `QualityColorHex`, `FormatGoldValue`, `LookupItemInfo`, plus class color tables. Migrate:

```lua
-- Before
local color = QUALITY_NUM_COLORS[quality]
return "|cff" .. color .. name .. "|r"
-- After
return cw:QualityColorName(name, quality)
```

```lua
-- Before
return string.format("%dk gold", math.floor(gold/1000))
-- After
return cw:FormatGoldValue(gold)
```

`LookupItemInfo` is FlipQueue-specific (touches `ns.db` for inventory fallback); keep it local. `cw:ResolveItemID(queueItem, lookupByName)` covers the same job for callers that pass an inventory lookup callback, but `UI/Shared.lua`'s closure over `ns.db` is convenient for FlipQueue and the migration cost outweighs the benefit.

## Phase 10 — Cleanup

After the above land:
- Delete `UI/ScrollTable.lua`.
- Delete the local class-color / quality-color tables in `UI/Shared.lua`.
- Delete inline backdrop table definitions.
- Remove `UI/MinimapButton.lua`'s soft-degrade fallback (the dependency-free `LDBIcon:Register` branch) once Cogworks is unconditionally embedded — single Cogworks-only path is cleaner.

## File-by-file migration map

| FlipQueue file                | Primary primitives used                                              |
|-------------------------------|----------------------------------------------------------------------|
| `UI/MainFrame.lua`            | Theme + Backdrop; `CreateNavButton` for sidebar                      |
| `UI/SettingsFrame.lua`        | `CreateTabPanel`, `CreateCollapsibleSection`, `CreateSettingsCheckbox / Button / Input` |
| `UI/MinimapButton.lua`        | `RegisterCogMinimapButton` (already adopted)                         |
| `UI/MiniView.lua`             | `CreateMiniView`                                                     |
| `UI/ContextDrawer.lua`        | `CreateMiniView`                                                     |
| `UI/ToolDrawer.lua`           | `CreateMiniView`                                                     |
| `UI/SetupWizard.lua`          | `CreateWizard`                                                       |
| `UI/TutorialPage.lua`         | `CreateWizard` (if multi-step)                                       |
| `UI/ResearchPage.lua`         | `CreateTree`                                                         |
| `UI/AllocWidget.lua`          | `CreateReorderableList`                                              |
| `UI/CharactersPage.lua`       | `CreateScrollTable`                                                  |
| `UI/InventoryPage.lua`        | `CreateScrollTable`                                                  |
| `UI/GuildsPage.lua`           | `CreateScrollTable`                                                  |
| `UI/LogPage.lua`              | `CreateScrollTable`                                                  |
| `UI/GeneratorPage.lua`        | `CreateScrollTable`, `CreateButton`                                  |
| `UI/TransformPage.lua`        | `CreateScrollTable`, `CreateButton`                                  |
| `UI/DealFinderPage.lua`       | `CreateScrollTable`, `CreateSettingsInput / Dropdown` (filters)       |
| `UI/DealFinderDetail.lua`     | `CreateScrollTable`                                                  |
| `UI/TodoPage.lua`             | `CreateScrollTable`                                                  |
| `UI/ExportPage.lua`           | `CreateScrollTable`, `CreateSettingsInput / Dropdown`                 |
| `UI/ExportPopup.lua`          | `CreatePopup`, `CreateTabPanel` (export modes), Forms                |
| `UI/ImportPage.lua`           | Forms; optionally `CreateWizard` for step-through import             |
| `UI/BankPopup.lua`            | `CreatePopup`, Forms                                                 |
| `UI/TSMFrame.lua`             | `CreatePopup`, Forms                                                 |
| `UI/TSMGroupTree.lua`         | `CreateTree` (TSM groups are hierarchical too)                       |
| `UI/UntrackedSection.lua`     | `CreateCollapsibleSection`                                           |
| `UI/DebugPage.lua`            | `CreateScrollTable`, Forms                                           |
| `UI/DebugConsole.lua`         | `CreateScrollTable`, `CreateSettingsInput`                           |
| `UI/Shared.lua`               | Migrate `QualityColorName` / `FormatGoldValue` to `cw:` equivalents; keep `LookupItemInfo` local |
| `UI/AuctionatorFrame.lua`     | `CreatePopup`, Forms                                                 |
| `UI/SlashCommands.lua`        | No UI changes                                                        |

## What stays in FlipQueue

- All slash commands (`/fq`, `/flipqueue`).
- `FlipQueueDB` saved variables.
- All auction / tracker / research / scanner business logic (`Tracker*.lua`, `Scanner.lua`, `AuctionPost.lua`, `AuctionAutoScan.lua`, `BankQueue.lua`, etc.).
- Domain-specific status colors (auction-state colors that aren't part of `cw.Theme.quality` or class colors).
- `LookupItemInfo` — has FlipQueue-DB inventory fallback baked in; migration cost outweighs the benefit. `cw:ResolveItemID` covers the same shape with a callback if Tally / Maxcraft need it.

## Estimated scope (revised)

The earlier estimate of 80–120 lines was way under. Realistic numbers with the full primitive set available:

| Phase                                  | Lines removed (approx) |
|----------------------------------------|------------------------|
| Theme constants (Phase 1)              | 30–40                  |
| Base widget consolidation (Phase 2)    | 80–120                 |
| Settings rewrite (Phase 3)             | 200–300                |
| ScrollTable migrations (Phase 4)       | 600–900 (deletes `UI/ScrollTable.lua` whole) |
| Mini views / drawers (Phase 5)         | 200–300                |
| Wizards (Phase 6)                      | 150–250                |
| Tree / reorder (Phase 7 + 8)           | 300–500                |
| Text helpers (Phase 9)                 | 50–80                  |
| Cleanup (Phase 10)                     | 80–120                 |
| **Total**                              | **~1,700 – 2,600**     |

Net LOC delta will be smaller after Cogworks calls + FlipQueue-specific config tables are added back, but the **maintenance surface** shrinks dramatically: every UI primitive becomes versioned-and-shared instead of duplicated across the suite.

## Sequencing

The user's prioritization (FQ-side):
1. **#18** — font size / scale settings (player ask). Phase 1 (theme), Phase 2 (base widgets), and Phase 3 (settings rewrite using Forms) are sufficient.
2. **#14** — biggest LOC win, MainFrame migration. Phase 4 (ScrollTable migrations) is the bulk of this; Phase 1–3 should be done first to give MainFrame's pages a consistent theme.
3. **#15** — drawers + popup migration. Phase 5 (mini views + drawers) plus the popup migrations from Phase 2.

Phase 6 (wizards) / 7 (tree) / 8 (reorder) slot in alongside #14 / #15 as their consumer files come up. Phase 9 (text helpers) is small enough to do in parallel with any of the others.
