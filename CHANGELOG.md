# Changelog

All notable changes to Cogworks-1.0 are tracked here. The library is **additive only** — old APIs never disappear, so every entry below is something gained, never lost.

## [Unreleased]

Bumps MINOR from `12` to `15`. Phase A + Phase B primitives for the FlipQueue migration (#1).

### Added
- **Tree** (`Cogworks-1.0/Tree.lua`) — `lib:CreateTree(parent, opts)`. Hierarchical expand/collapse list. Each node is `{ key, label, count?, children? }`. Chevrons render only on branches; click the chevron half of the row to toggle expansion, click anywhere else to select. Supports `Expand(key)`, `Collapse(key)`, `Toggle(key)`, `ExpandAll()`, `CollapseAll()`, `SetSelected(key)`, `GetSelected()`. Phase C item from #1, used by FlipQueue's `ResearchPage`. Non-virtualized for v1 — fine up to a few hundred visible nodes. (MINOR 15)
- **Reorderable list** (`Cogworks-1.0/ReorderableList.lua`) — `lib:CreateReorderableList(parent, opts)`. Drag-to-reorder vertical list. Caller owns row contents via `opts.renderRow(row, item, index)`; `opts.onReorder(items, fromIndex, toIndex)` fires on drop. Uses a row pool — `renderRow` is called whenever the row is reused, so cache child widgets on the row table. Phase C item from #1, used by FlipQueue's `AllocWidget`. (MINOR 15)
- **Wizard** (`Cogworks-1.0/Wizard.lua`) — `lib:CreateWizard(parent, opts)`. Multi-step flow widget. Header shows the current step title plus one progress dot per step (gold for completed/active, dim for upcoming); footer has Cancel / Previous / Next (becomes Finish on the last step). Per-step `validate()` gates Next; callers wire `wizard:Refresh()` to revalidate after user input. `onComplete` fires on Finish click; `onCancel` on any-step Cancel; `onStepChange(key, idx)` for telemetry. Step pages are lazy-built. Phase B item from #1. (MINOR 15)
- **Mini view frame** (`Cogworks-1.0/MiniView.lua`) — `lib:CreateMiniView(opts)`. Heads-up frame with the suite's standard chrome (title bar, pin, close, resize grip). Position / size / pinned state persist into a caller-supplied savedvars table. Pin locks the frame and hides the resize grip; close fires `opts.onClose`. Honors the suite's `uiScale` setting via `SettingsChanged`. Phase B item from #1. (MINOR 15)
- **Rich-text helpers** (`Cogworks-1.0/Text.lua`) — `lib:QualityColorName(name, quality)`, `lib:QualityColorHex(quality)`, `lib:ClassColor(class)`, `lib:ClassColorName(name, class)`, `lib:FormatGoldValue(gold)`, `lib:FormatGSC(copper)`, `lib:FormatGoldShort(copper)`. Quality accepts numeric IDs or canonical name strings; class accepts upper-case keys (`"WARRIOR"`, `"DEATHKNIGHT"`, ...). Gold formatting comes in three flavors so cogs can pick the precision they want. Lifted from FlipQueue's `UI/Shared.lua`. Phase B item from #1. (MINOR 15)
- **Tab panel** (`Cogworks-1.0/TabPanel.lua`) — `lib:CreateTabPanel(parent, opts)`. Inline horizontal tab strip with content area below; tab pages are lazy-built on first activation, tabs auto-size to their label width with a 60 px floor and reflow on `fontScale` / `fontFamily` change. Distinct from `CreateNavButton` (sidebar nav). Phase B item from #1. (MINOR 15)
- **Section dynamic content height** — `lib:CreateCollapsibleSection`'s `opts.contentHeightFn` and `section:SetContentHeightFn(fn)`. When set, `applyLayout` calls the fn fresh on every pass instead of using a stored value, and the section schedules a one-shot `OnUpdate` settle whenever it shows content — so wrapping body FontStrings size correctly even when their wrapped height isn't measurable until WoW renders the next frame. The existing `SetContentHeight(h)` static API is unchanged. (MINOR 14)
- **Per-module load guards** — every Cogworks module file (`Sections`, `Forms`, `Icons`, `Items`, `Realms`, `API`, `TabPanel`) tracks a `MODULE_MINOR` on `lib._modules.<Name>`; older copies vendored by sibling cogs that load after a newer standalone copy now skip cleanly instead of clobbering the newer methods. (MINOR 14)
- **Settings form helpers** (`Cogworks-1.0/Forms.lua`) — `lib:CreateSettingsCheckbox(parent, opts)`, `lib:CreateSettingsButton(parent, opts)`, `lib:CreateSettingsInput(parent, opts)`. Labeled-row variants of the base primitives. Each returns `(row, consumedHeight)` for y-cursor auto-layout. All rows re-font and re-lay on `SettingsChanged` (`fontScale` / `fontFamily`); callers wanting a stack reflow can subscribe via `opts.onHeightChanged` or re-walk via `row:GetConsumedHeight()`. (#1, MINOR 13)
- **`lib:CreateDropdown` auto-width option** — additive 5th argument `opts` accepting `autoWidth` (bool), `minWidth`, `maxWidth`, `width`. With `autoWidth = true`, the dropdown measures each item's label and fits to the widest, clamped by min/max. Re-fits on `SetItems` and on `SettingsChanged` font changes. Also: dropdown menu now flips up when there isn't room below the dropdown anchor (bottom-of-frame / bottom-of-screen case). Existing four-arg callers are unaffected. (#1, MINOR 13)

### Fixed
- **Minimap gear ring sized at 32 px** instead of 53. CogBorder.tga's silhouette fills nearly the full 128×128 texture rect; LDBIcon's 53×53 default is sized for a much sparser ring asset and made the gear visually ~70% larger than the button. Tally tuned to 32 in its pre-adoption overlay-swap workaround; the Cogworks helper now matches.
- **Maxcraft and Tally edge gears mesh** with the cluster's hub and core trio. Earlier `CLUSTER_POSITIONS` floated them well above the meshed core; pulled down to y=17 with the same ~5 px overlap as the FQ↔CW↔TM mesh.

## [0.10.0] — Embedded-layout minimap fix, icon registry, gear assembly chrome

Bumps MINOR from `9` to `12`. Resolves issues #9, #10, #11, #13.

### Added
- **Suite-wide icon registry** (`Cogworks-1.0/Icons.lua`) — `lib:RegisterIcon(name, def)`, `lib:ApplyIcon(texture, name)`, `lib:HasIcon(name)`. Built-in `chevron-right` and `chevron-down` resolve to friendslist atlases. Solves the recurring "WoW default fonts don't ship the Unicode Geometric-Shapes block, so `▶ ▼` render as missing-glyph boxes" problem once instead of per-widget. Cogs register their own variants via `RegisterIcon`. (#9)
- **Gear assembly cluster + row layouts** — `lib:CreateGearAssembly(parent, opts)` accepts `opts.layout = "cluster"` (default) or `"row"`. Cluster places Cogworks at the hub with FlipQueue + Tempo as the meshed core trio (counter-rotating, periods scaled by tooth velocity at contact); Maxcraft and Tally float as edge gears. Row mode is linear with thin connector bars. Always-on animation — saturation + `?` / `...` overlays carry install-state signal. (#11)
- **Bundled minimap chrome ships with the library** — `CogBorder.tga` and per-cog inner-glyph TGAs (`fq-inner`, `tm-inner`, `mc-inner`, `tl-inner`, `cw-inner`) moved into `Cogworks-1.0/Art/` so embedded consumers receive them via the existing `path: Cogworks-1.0` external. New `libArtPath` helper centralizes path resolution and captures the loader addonName at file load. (#13)
- **`Tally` added to `lib.SuiteRoster`** — renders in the gear assembly with its own inner glyph.
- **`innerIcon` and `cluster` fields on roster entries** — layout slot decision (`hub` / `core` / `edge`) lives in the roster, not the widget.

### Fixed
- **`RegisterCogMinimapButton` now works in embedded layout** — previous wrapper called `LibDBIcon:SetButtonBorder` (only on v56+; Tally vendored v44) and hard-coded `Interface\AddOns\Cogworks\Art\CogBorder` which doesn't resolve when consumers have no top-level `Cogworks` folder. New implementation adopts Tally's overlay-texture pattern: `LibDBIcon:Register`, hide the default tracking-border region, add a gear OVERLAY child texture. Works on every LibDBIcon version. (#10)
- **`libArtPath` standalone-vs-embedded detection is now case-insensitive** — comparison was `== "Cogworks"` but `cogworks.toc` is lowercased, so standalone resolution fell through to the embedded path. Comparison is now `:lower() == "cogworks"`.
- **Inner-glyph-to-ring gap closed** — visual seam between the inner glyph and the gear ring.

### Removed
- **`Ledger` cog name purged** — Tally is the suite's ledger. Roster entry, gear-assembly slot, and docs all updated.

> **Note**: Releases 0.4.0–0.9.0 shipped without changelog entries. Their work is captured in closed issues #3 (minimap gear-border), #4 (icon readability), #5 (versioned cross-cog API registry — `Cogworks-1.0/API.lua`), #6 (item-key + realm helpers — `Cogworks-1.0/Items.lua`, `Cogworks-1.0/Realms.lua`), #7 (standalone dev console), and #8 (RegisterCogMinimapButton initial). `CreateCollapsibleSection` (`Cogworks-1.0/Sections.lua`) shipped as the v0.9.0 starter for #1 Phase A.

## [0.3.0] — Font scaling, settings, and gear assembly

Bumps MINOR from `2` to `3`. Adds accessibility-focused customization and the suite gear assembly widget.

### Added
- **Settings system** — `lib.settings` with `GetSetting`, `SetSetting`, `ApplySettingsTable`, `GetSettingDefaults`. Fires `SettingsChanged` event when values change. Standalone addon persists settings in `CogworksDB`.
- **Font scaling** — `lib.Fonts.normal`, `.small`, `.large`, `.header` — named FontObjects that respect `lib.settings.fontScale` (0.8x–1.4x). All widget factories now use these instead of hardcoded `GameFontNormal`, so every Cogworks-built widget scales together when the user adjusts font size.
- **`lib:UpdateFonts()`** — rebuilds all FontObjects at the current scale. Called automatically when `fontScale` changes.
- **`lib:GetFont(key)`** — returns a FontObject by key (`"normal"`, `"small"`, `"large"`, `"header"`).
- **UI scale setting** — `lib.settings.uiScale` for cogs to apply via `frame:SetScale()`.
- **Suite roster** — `lib.SuiteRoster` lists all known cogs (FlipQueue, Tempo, Maxcraft, Tally) with role, icon, and URL metadata. Used by the gear assembly to show installed vs. missing members.
- **`lib:CreateGearAssembly(parent, opts)`** — compact widget showing every cog as a connected gear. Installed cogs spin in brass with circular-masked icons; missing cogs are grayed out with "?" overlay and click-for-link; planned cogs show "..." in arcane purple. Auto-refreshes when cogs register. Options: `showLabels` (default true).
- **Showcase: Gear Assembly page** — default landing page showing full and compact assembly variants plus registry info.
- **Showcase: Settings page** — font scale buttons (80%–140%) with live preview, UI scale controls, reset-to-defaults, and live widget demo.
- **`CogworksDB` SavedVariables** — standalone addon persists non-default settings across sessions.

## [0.2.0] — UI widget factories

Bumps MINOR from `1` to `2`. Adds shared UI primitives so cogs can stop duplicating the same themed widget code.

### Added
- **Theme expansions** — `header`, `sidebar`, `rowAlt`, `rowHover`, `textDim`, `textDisabled` entries in `lib.Theme` covering all the UI-level constants that were duplicated across Tempo, Maxcraft, and FlipQueue.
- **Backdrop templates** — `lib.Backdrop` (16px edge) and `lib.BackdropSmall` (10px edge) replacing per-cog `UI.BACKDROP` / `UI.BACKDROP_SMALL` definitions.
- **`:CreateButton(parent, label, width, height, onClick)`** — themed button with dark background, gold-accent hover, and press feedback.
- **`:CreateCheckbox(parent, label, description, initialValue, onChange)`** — checkbox with label and optional description text, including sound feedback.
- **`:CreateIconButton(parent, icon, size, tooltip, onClick)`** — minimal icon-only button with highlight and optional tooltip.
- **`:CreateSectionHeader(parent, text, yOffset)`** — uppercase gray divider label for organizing settings and page sections.
- **`:CreateProgressBar(parent, width, height)`** — progress bar with fill texture and text overlay; provides `:SetProgress(current, max)` and `:SetBarColor(r, g, b)`.
- **`:CreateNavButton(parent, navItem, onClick)`** — sidebar navigation button with icon, label, optional badge, gold accent bar, and active/inactive state.
- **`:SetNavButtonActive(btn, isActive)`** — toggle a nav button's active visual state.
- **Migration plans** — `docs/migration/flipqueue.md`, `docs/migration/tempo.md`, `docs/migration/maxcraft.md` with step-by-step instructions for each cog to adopt the shared UI.

## [0.1.0] — Initial release

First public version of `Cogworks-1.0`, the shared mainspring of the Cogworks WoW addon suite.

### Added
- **LibStub library `Cogworks-1.0`** (MINOR `1`) — embeddable into any cog via `.pkgmeta` externals.
- **Event bus** — `CallbackHandler-1.0`-backed registry with a canonical `lib.Events` table covering lifecycle (`Ready`, `AddonRegistered`), character/account state (`CharacterChanged`, `GoldChanged`), inventory signals (`InventoryChanged`, `MailChanged`, `AuctionsChanged`), and suite domain events (`SaleLogged`, `CraftCompleted`, `ResetDue`, `PriceUpdated`).
- **Addon registry** — `:RegisterAddon`, `:GetAddon`, `:GetRegisteredAddons` so any cog can enumerate its installed siblings.
- **Print helpers** — `:Print` and `:PrintError` with branded per-cog chat prefixes.
- **Theme palette** — dark base, gold primary, arcane-purple highlight, brass clockwork trim, plus status colors and WoW item-quality colors.
- **Character key utilities** — `:GetCharacterKey()` returning canonical `"Name-RealmNormalized"` strings that match Syndicator's convention.
- **Syndicator capability bridge** — `:HasSyndicator()` for cogs that want to opportunistically enrich data when Syndicator is present, without making it a hard dependency.
- **Standalone shell** — `/cogworks` slash command (`status`, `events`, `fire <ev>`, `help`) for local development and verification. Ships only in the standalone CurseForge/Wago install; embedded copies do not include it.
