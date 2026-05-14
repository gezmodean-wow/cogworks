# Changelog

All notable changes to Cogworks-1.0 are tracked here. The library is **additive only** — old APIs never disappear, so every entry below is something gained, never lost.

## [0.14.2] — 2026-05-14 — Appearance-tab convention (COG-71)

Bumps `MINOR` from `27` to `28`. Names the standard cogworks-managed appearance controls and the canonical adoption shape for sibling cogs. No player-visible behaviour change — additive library work for cog authors.

### Added

- **`cw:CreateAppearanceTab(parent, opts)` + adoption convention** (`Cogworks-1.0/Scaling.lua`, MODULE_MINOR `2 → 3`, COG-71) — additive clear-intent alias for `CreateUIScalingSettingsBlock`. Both functions are identical; the new name names the convention: every cog's settings UI ends with an **"Appearance"** tab whose body is a single `cw:CreateAppearanceTab(parent, { cog = "MyCog" })` call. Cog-specific toggles / pickers go in **other** tabs; Appearance is reserved for the standard suite-wide primitive so future UX improvements (theme color editor, new overrides, etc.) reach every cog the day they ship. All writes flow through cogworks into `CogworksSharedDB`. Per-cog overrides for `fontScale` + `fontFamily` are scoped to `cog`; `uiScale` + theme stay suite-wide for the v0.14.x line (per-cog theme is the multi-release stretch tracked in #74). Adoption tickets filed on Tally + FlipQueue trackers; showcase page at `/cogworks ui` → "Appearance tab" demos the canonical pattern.

### Notes

- Consumer cogs should re-pin `.pkgmeta` Cogworks external to v0.14.2 to pick up `CreateAppearanceTab`. v0.14.1 callers can use `CreateUIScalingSettingsBlock` with the same opts — the convention is identical, only the name changes.

## [0.14.1] — 2026-05-14 — CreateDebugConsole tab-overlap hotfix (COG-69)

Bumps `MINOR` from `26` to `27`. Hotfix for a developer-visible regression unmasked by v0.14.0: switching between Actions / Inspectors / Profile / Log tabs in `CreateDebugConsole` no longer hides the previous tab's chrome, so all four tabs' contents pile onto the shared content frame and overlap visibly.

### Fixed

- **`CreateDebugConsole` tab overlap on tab switch** (`Cogworks-1.0/Debug.lua`, MODULE_MINOR `3 → 4`, COG-69) — each of `_buildActions` / `_buildInspectors` / `_buildProfile` / `_buildLog` now wraps its chrome in a per-tab page frame and returns it, and the tab `build` thunks pass that return value through to `TabPanel`. Previously the builders added children directly to the shared content frame and returned nothing, leaving `TabPanel.tabPages[key]` nil — so `setActive` had nothing to `Hide()` on the previous tab and the chrome accumulated. Latent since v0.13.0, but masked by COG-56 (`attempt to call a nil value` on initial activation) until v0.14.0; clicking a different tab in the console now correctly swaps the visible content.

### Notes

- Consumer cogs should re-pin `.pkgmeta` Cogworks external to v0.14.1. Per-module guards mean a single v0.14.1 install supersedes vendored v0.14.0 `Debug.lua` copies, but every cog should still re-pin for safety.

## [0.14.0] — 2026-05-14 — Async + interaction primitives, FQ-audit feed-in

Bumps `MINOR` from `19` to `26`. Eight new / extended primitives from the FlipQueue v0.13 adoption audit (FQ #143) plus two fixes — one player-visible (standalone minimap inner-glyph artwork) and one developer-visible (debug console crash on open).

### Player summary

If you run **standalone Cogworks**, the suite minimap cog now displays its inner-glyph artwork correctly on packaged CurseForge / Wago builds. Earlier releases shipped without the inner-glyph TGA due to a packager substring-match quirk on the `.pkgmeta` ignore list — the icon rendered with a missing-texture placeholder. No action required; just update.

If you don't run standalone Cogworks, this release is purely a library API expansion for sibling cogs (FlipQueue, Tempo, Maxcraft, Tally) and has no player-visible effect on your installs until those cogs adopt it.

### Added

- **`lib:CreateStepper(parent, opts)`** (`Cogworks-1.0/Stepper.lua`, COG-36) — queue-based one-at-a-time walkthrough primitive; Wizard's sibling for unknown-length item flows. Caller-defined footer actions, Push during traversal, Skip / Back / Cancel / onComplete. Distinct from `CreateWizard` (fixed-N linear setup with validate gate). Unblocks FlipQueue's Deal Finder migration and FlipQueue #160 (failed-post recovery).
- **`CreateDrawer` edge-reveal animation** (`Cogworks-1.0/Drawer.lua`, MODULE_MINOR `2 → 3`, COG-38) — additive `opts.animate = { direction, duration, easing, distance }` to slide-and-fade the drawer in from its anchor edge over a configurable duration. `direction` is `"right" | "left" | "up" | "down"`; default duration 0.15s, easing `"out"`. Mid-flight Show / Hide / Toggle reverse cleanly; ESC during a Show animation cancels Show and plays the Hide reverse. `nil opts.animate` preserves the original instant-show/hide behavior bit-exact. Unblocks FlipQueue's ToolDrawer / ContextDrawer migrations (FQ #143 phase C).
- **`lib:ShowLoading(parent, opts)`** (`Cogworks-1.0/Loading.lua`, COG-40) — async-state overlay primitive. Returns a handle with `:SetText`, `:SetProgress`, `:Hide`, `:GetProgress`, `:IsShown`. Indeterminate mode (default) shows a five-dot gold wave-pulse; passing a number to `SetProgress` flips to a determinate brass status bar with a percent suffix. `cancelable = true` adds a close X and ESC handling that fires `onCancel`; `dimBackground = true` dims the parent and swallows click-through. Banner centers on parent by default; caller can re-anchor via `handle.banner`. Replaces the bespoke "loading…" banners across FlipQueue (`GeneratorPage`, `DealFinderPage`, `ImportPage`, `ResearchPage`) and forward-compats Tally / Maxcraft async paths.
- **`CreateMiniView` `opts.persistKeys` opt-in** (`Cogworks-1.0/MiniView.lua`, MODULE_MINOR `16 → 17`, COG-41) — additive whitelist of which geometry keys (`x`, `y`, `width`, `height`, `pinned`) the mini view reads from and writes to `opts.savedvars`. Omitted or `nil` preserves the v0.13.x default (persist everything). Cogs whose pinned/collapsed state should default fresh on each login pass e.g. `{ "x", "y", "width", "height" }` and the `pinned` key becomes session-only. Keys outside the list are never written; on Show they read the in-memory defaults instead of `sv`. Lands the workaround that FlipQueue / Tally / Maxcraft would have otherwise re-rolled per cog.
- **CreateDebugConsole per-cog action registry** (`Cogworks-1.0/Debug.lua`, MODULE_MINOR `2 → 3`, COG-43) — `RegisterDebugAction` now accepts an opts table in addition to the existing `(cog, label, fn)` positional shape: `{ label, run, group?, help?, disabled? }`. The console groups actions by `group` (registration-order within group, group-first-appearance across groups) and renders a small section header for each named group. `disabled = true` renders the button dim and unclickable; `help` shows a hover tooltip. New `cw:UnregisterDebugAction(cog, label)` removes by label. `cw:GetDebugActions()` with no arg returns a `{ [cog] = actions }` map across every registered cog. The console auto-rebuilds on any later Register/Unregister via a per-cog rebuild list, so cogs that lazily register actions late in load no longer need to manually refresh. Empty-state hint also updated to advertise the richer opts-table form.
- **`lib:ShowItemKeyTooltip` / `lib:HideItemKeyTooltip`** (`Cogworks-1.0/Items.lua`, MODULE_MINOR `14 → 15`, COG-44) — wraps the regular-item / battle-pet fork and the uncached-item fallback in one call. `cw:ShowItemKeyTooltip(owner, anchor, itemKey, { fallbackText, onLoad, tooltip })` sets the tooltip owner, dispatches `SetHyperlink` for items / `SetHyperlink("battlepet:...")` for pet keys, falls back to a "Loading..." text when `GetItemInfo` returns nil and queues a `C_Item.RequestLoadItemDataByID`; `onLoad` fires once when the cache settles. A single shared listener frame drains the `ITEM_DATA_LOAD_RESULT` queue so per-row tooltip calls don't leak event frames. Replaces the recurring 6+ near-identical tooltip-setup blocks across FlipQueue (`UI/TodoPage`, `UI/InventoryPage`, `UI/DealFinderDetail`, `UI/ResearchPage`, `UI/GeneratorPage`) and lands the consistent pet-link handling that some sites currently miss.
- **`CreateWizard` per-step custom footer** (`Cogworks-1.0/Wizard.lua`, MODULE_MINOR `15 → 16`, COG-53) — additive `step.footer = function(footerFrame, api)` callback per step. When set, the wizard's standard Cancel/Previous/Next row hides for that step and the caller's builder fills the footer with whatever buttons make sense. `api` exposes `Next`, `Previous`, `GoTo(key)`, `Cancel`, `Finish` so custom buttons drive navigation. Children are built lazily on first activation and shown/hidden on subsequent visits. Default behavior unchanged for steps without `footer`. Unblocks FlipQueue's SetupWizard welcome screen (dual "Use defaults" / "Customize" CTAs that branch the flow).
- **`lib:CreateTaskProgress` + `lib:CreateMultiTaskProgress`** (`Cogworks-1.0/TaskProgress.lua`, new module, COG-23) — dockable long-running task-progress widget. Single-bar variant has its own chrome (title + cancel X), label / progress / ETA-suffix slots, and a 1.5s linger + 0.6s fade on `:Complete()`. Multi-row variant stacks per-source rows inside a shared title-barred panel and exposes `panel:GetRow(key)` for chained updates (`row:SetTotal(n):SetValue(v):SetETA(t)`). Per-row state colours (`queued | importing | done | error | skipped`) convey status at-a-glance across a stack; `:Pulse()` runs a 40px sliding-highlight indeterminate animation and calling `:SetValue(n)` flips back to determinate without flicker. Row dimensions stay fixed across label/ETA mutations so a multi-source import doesn't jitter mid-run. Position persists into `opts.savedvars` when supplied. **Naming note:** named `CreateTaskProgress` (not `CreateProgressBar`) to avoid colliding with the existing inline-cell `cw:CreateProgressBar(parent, width, height)` primitive — that one stays for in-table use; this module is for the standalone "background work happening" widget. v1 drivers: Tally's multi-source import controller (TSM CSV + FlipQueue + Journalator) and Tally's on-demand period-synthesis flow.

### Fixed

- **CreateDebugConsole crash on open** (`TabPanel.lua` MODULE_MINOR `15 → 16`; `Debug.lua` MODULE_MINOR `1 → 2`; COG-56) — TabPanel's eager initial activation fired tab `build` closures that referenced `f._buildActions` / `_buildInspectors` / `_buildProfile` / `_buildLog` before those methods are defined further down in `CreateDebugConsole`. TabPanel gains an additive `lazy = true` opt that suppresses the auto-activate; `Debug.lua` passes it and now calls `panel:SetActiveTab(...)` once every builder is wired. Cogs that wired up `CreateDebugConsole` after v0.13.0 hit `attempt to call a nil value` immediately on `:Show()` — fixed.
- **Standalone minimap icon ships without inner-glyph TGA** (`.pkgmeta`, COG-55) — `.pkgmeta` previously listed `Art/inner` under `ignore:` to skip the top-level source-PNG dir, but BigWigsMods packager treats ignore patterns as substring matches so the same rule also stripped `Cogworks-1.0/Art/inner/` — the runtime TGA directory referenced from `Standalone\Standalone.lua:139` (the `cw-inner` icon) and from `Cogworks-1.0/Cogworks-1.0.lua:1056` (the SuiteRoster `innerIcon` map). Packaged CurseForge/Wago builds rendered a missing-texture placeholder. Removed the entry; source PNGs (~50KB) now ride along in the release zip. No code change.

### Notes

- **All consumer cogs should bump their `.pkgmeta` Cogworks external to v0.14.0 and re-release** to pick up the COG-55 packaging fix and the new primitives. Per-module guards mean a single v0.14.0 install (standalone or via any consumer cog) supersedes older vendored copies, but the safest posture is for every cog to re-pin.
- The investigation sub-issue for the cross-realm service extraction (#2) is captured in #68 — an end-to-end inventory of FlipQueue's realm-touching code, ready for a future design pass.

## [0.13.2] — 2026-05-05 — Critical: StaticPopupDialogs taint hotfix (COG-30)

Bumps MINOR from `18` to `19`. Hotfix for a long-latent taint introduced in v0.12.0 that blocked the player from right-clicking certain bag items (most visibly knowledge tomes and consumables that show a confirmation prompt on use).

### Player summary

If you've had bag items that quietly refused to be right-clicked — knowledge tomes, profession consumables, or anything that pops a "use this?" confirmation — this update fixes that. The same items now use normally. No settings change required; just update Cogworks (and your cogs once they re-release pinned to this version).

### Fixed

- **`Scaling.lua`** (MODULE_MINOR `1 → 2`) — removed the `StaticPopupDialogs = StaticPopupDialogs or {}` defensive rebind at the top of the profile-popup registration block. That rebind taints the `StaticPopupDialogs` global from insecure context; from then on, any protected Blizzard call that consults the popup table inherits taint. Most user-visible: `UseContainerItem` on items that pop a confirmation StaticPopup (knowledge tomes, certain consumables). The right-click silently fails with `ADDON_ACTION_FORBIDDEN AddOn 'cogworks' tried to call the protected function 'UNKNOWN()'` from `ContainerFrameItemButton_OnClick`. Items that don't trigger a confirmation popup (gear, tradegoods) were unaffected — that asymmetry was the diagnostic signal. The per-key assignment pattern below the deleted line (`StaticPopupDialogs["COGWORKS_NEW_PROFILE"] = ...`) is the safe, standard pattern and stays. (COG-30)

### Notes

- **All consumer cogs must bump their `.pkgmeta` Cogworks external to v0.13.2 and re-release.** The taint was in `Scaling.lua`, so any cog vendoring v0.12.0–v0.13.1 still ships the bug until they re-pin. The per-module guard (MODULE_MINOR 2) ensures that if *any* loaded cog ships v0.13.2, the fixed file supersedes older copies — but every cog should still bump for safety.
- Standalone Cogworks users running v0.12.0–v0.13.1 should update immediately.

## [0.13.1] — 2026-05-03 — Critical: ESC handler taint hotfix (COG-26)

Bumps MINOR from `17` to `18`. Hotfix for a critical taint introduced in v0.13.0 that locked the player out of the game menu after they opened (and closed) any Cogworks-themed window.

### Player summary

If you've used Tally (or any cog built on Cogworks v0.13.0) you may have hit a bug where pressing Escape stopped opening the game menu — and you couldn't logout or quit the game without /reload. This release fixes that. Update Cogworks (and your cogs once they re-release with this version pinned) and the game menu will work normally again.

### Fixed

- **`CreateThemedMainFrame`** (`ThemedMainFrame.lua`, MODULE_MINOR 1 → 2) — replaced the ESC-to-close handler with `UISpecialFrames` registration. The previous `EnableKeyboard` + `OnKeyDown` + `SetPropagateKeyboardInput(false)` pattern tainted the secure execution path that `ToggleGameMenu` walks to call `ClearTarget` (UIParent.lua:2389), so every ESC press after the cog's frame had been opened raised `ADDON_ACTION_FORBIDDEN AddOn 'cogworks' tried to call the protected function 'ClearTarget'` and silently swallowed the keypress. Players reported full game-menu lockout (no logout, no quit) until /reload. The fix uses Blizzard's supported escape-to-close mechanism, which requires a globally named frame — callers already pass `opts.name`, so no API change. (COG-26)
- **`CreateDrawer`** (`Drawer.lua`, MODULE_MINOR 1 → 2) — same fix, preventive. ESC support now requires `opts.name`; nameless drawers silently skip the bind rather than ship the broken handler.
- **`CreatePopup` / `ShowConfirmDialog`** (`Cogworks-1.0.lua`) — same fix. The popup overlay now auto-generates a unique global name (`CogworksPopupOverlay_N`) and registers it with `UISpecialFrames` so ESC actually closes the popup (the previous `OnKeyDown` was dead code anyway because `EnableKeyboard` was never called on the overlay).

### Notes

- **All consumer cogs must bump their `.pkgmeta` Cogworks external to v0.13.1 and re-release.** Until they do, vendored copies of the buggy `ThemedMainFrame.lua` / `Drawer.lua` will still load when the cog is installed without the standalone Cogworks addon. The per-module guard (MODULE_MINOR 2) ensures that if *any* loaded cog ships v0.13.1, the fixed methods supersede older copies — but the safest posture is for every cog to ship the bump.
- Standalone Cogworks users running v0.13.0 should update to v0.13.1 immediately.

## [0.13.0] — 2026-05-02 — Debug toolkit, ThemedMainFrame, Drawer, Slash, Toast

Bumps MINOR from `16` to `17`. Resolves cogworks #14 (ThemedMainFrame), #15 (Drawer), #16 (Slash registry), #17 (Toast). Adds the per-cog **debug toolkit** that consumer cogs can adopt out of the box (logger + inspectors + profiler + console widget + state-dump dialog + lib-side debug bridge). Standalone Cogworks now ships its own gear-bordered minimap button.

### Added

- **Debug toolkit** (`Cogworks-1.0/Debug.lua`) — per-cog state, all keyed by `cogName`:
  - **Logger**: `lib:RegisterDebugLogger(cog, opts)` returns a logger object with `:PrintDebug(...)`, `:GetEntries()`, `:Clear()`, `:OnAppend(cb)`, `:SetEnabled(b)`/`:IsEnabled()`. 500-line ring buffer (configurable). Chat echo gated by enabled flag; lib also exposes the bare entrypoints `lib:DebugPrint(cog, ...)`, `lib:ClearDebugLog(cog)`, etc.
  - **Inspectors**: `lib:RegisterDebugInspector(cog, name, fn)` registers a named state accessor; `lib:DumpDebugState(cog)` concatenates all inspectors + suite settings + profile stats + recent log into one copy-friendly blob.
  - **Profiler**: `lib:Profile(cog, label, fn, ...)` wraps a call with `debugprofilestop()` timing. Per-label `{count, total, last, max, avg}` counters; `lib:GetProfileStats(cog)` / `lib:ResetProfileStats(cog)`. Skips timing when the cog's debug is disabled — zero overhead in production.
  - **Actions**: `lib:RegisterDebugAction(cog, label, fn)` adds a button to the dashboard.
  - **Serializer**: `lib:SerializeDebugValue(v, opts)` — recursive table-to-text printer, cycle-safe, sorted keys, biased toward defect-report readability.
  - **`lib:CreateDebugConsole(opts)`** — dashboard frame for one cog. Tabbed surfaces (Actions / Inspectors / Profile / Log), status row with toggle, copy-friendly state dumps, live-updated log, movable + resizable, optional persistence.
  - **`lib:CreateCopyDialog(text, hint?)`** — modal popup with read-only multi-line EditBox + Ctrl+A/C copy. Resizable; auto-highlights for one-stroke copy.
  - **`LibDebug` event + bridge** — new event name `LibDebug`. Lib internals fire it (via `lib:_LibDebugPrint(msg, scope?)`); every registered cog logger auto-subscribes and tags the entry `[Cogworks-1.0/<scope>]` in its own ring buffer. A single console shows both cog activity and lib activity without any wiring on the cog's end.
- **`lib:CreateThemedMainFrame(opts)`** (`Cogworks-1.0/ThemedMainFrame.lua`, #14) — one-call main window chrome: title bar (title + dim version), summary bar (optional one-line status), sidebar with drag-to-resize handle, content area, diagonal-dot resize grip, ESC-to-close, persisted geometry. `frame:AddNavItem(item)` / `frame:SetActivePage(key)` / `frame:SetSummary(text)` / `frame:SetPageBuilder(key, fn)` cover the common surface; auto-subscribes to `SettingsChanged.uiScale`. Replaces the ~300 LOC of chrome each cog hand-rolls in its `UI/MainFrame.lua`.
- **`lib:CreateDrawer(opts)`** (`Cogworks-1.0/Drawer.lua`, #15) — non-modal floating panel for tool drawers, context drawers, side popups. Title bar + close + drag, optional resizable + grip, optional anchor-to-parent on Show, ESC handler, persisted geometry. Distinct from `CreatePopup` (modal blocking) and `CreateMiniView` (heads-up). `drawer:Toggle()` / `:SetTitle()` / `:SetOnClose()` / `:SetAnchorTo()`.
- **`lib:RegisterSlashCommands(addonName, opts)`** (`Cogworks-1.0/Slash.lua`, #16) — owns SLASH_X1/SLASH_X2/SlashCmdList wiring + tokenizing input + case-insensitive subcommand match + auto-help (chat / popup / both). Each command gets `name`, `run`, optional `help`, `args`, `aliases`, `hidden`. `lib:AddSlashCommand(addonName, command)` for plugin-style late registration.
- **`lib:Toast(opts)`** (`Cogworks-1.0/Toast.lua`, #17) — transient banner with fade-in / fade-out, vertical stacking, severity → theme color mapping (`success` / `info` / `warning` / `error`), optional icon + onClick. Auto-dismiss after `duration` (default 3 s); pause-on-hover; click-to-dismiss; `lib:ClearToasts()` to flush all live toasts. Anchor configurable via `cw:SetSetting("toastAnchor", { point, relPoint, x, y })`.
- **Standalone Cogworks minimap button** — the standalone install now registers its own gear-bordered LDBIcon button via the suite's own `RegisterCogMinimapButton` primitive (meta-validation that the API works for its own addon). Left-click opens the UI showcase, right-click opens the dev console. SV under `CogworksDB.minimap`. Adds LDB + LDBIcon to the standalone TOC + .pkgmeta externals.
- **Mesh-spin easter egg** on cog minimap buttons — hovering or clicking any registered cog suite minimap button briefly spins (1 rotation, ~1.2 s) every other registered button. One-shot animation per cog so it stays cheap; skipped when an animation is already playing. Wired into `RegisterCogMinimapButton` so every cog gets the behavior automatically.
- **`/cogworks debug`** slash subcommand — toggles a `CreateDebugConsole({ cog = "Cogworks" })` instance for testing the toolkit against the standalone install.

## [0.12.0] — 2026-05-01 — Suite settings persistence + Phase D primitives

Bumps MINOR from `15` to `16`. Resolves cogworks #22 (suite-wide settings persistence) and the Phase D primitive batch (#21, #20, #19, #18). Theme / scale / font / profile settings now persist whether or not the standalone Cogworks addon is installed.

### Added

- **`CogworksSharedDB` shared persistence** — every cog declares `## SavedVariables: CogworksSharedDB` in its TOC; the lib hooks `ADDON_LOADED` / `PLAYER_LOGIN` / `PLAYER_LOGOUT` and reads/writes the active profile regardless of whether standalone Cogworks is installed. One-shot migration from the legacy `CogworksDB` runs the first time a session sees `schemaVersion == nil`. Standalone's parallel persistence block was removed; `CogworksDB` stays declared for one release as a downgrade safety net. (#22)
- **Profile system** — named bundles of settings stored under `CogworksSharedDB.profiles[name]`. New API: `lib:GetProfileNames`, `lib:GetActiveProfile`, `lib:SetActiveProfile`, `lib:CreateProfile(name, copyFrom?)`, `lib:DeleteProfile`, `lib:RenameProfile`, `lib:ExportProfile`, `lib:ImportProfile`. Profile switch fires `SettingsChanged` for every known key so font/theme/scale subscribers reflow. (#22)
- **Per-cog override (`fontScale` + `fontFamily`)** — `lib:SetCogProfile(cog, profileName)` points a cog at a different profile for its overridable settings while the rest of the suite stays on `activeProfile`. v1 override surface is intentionally narrow: `fontScale` and `fontFamily`. `uiScale`, `theme`, and `customThemes` stay suite-wide because their state is shared by mutable theme tables / FontObjects that every widget already references directly. New API: `lib:GetCogProfile`, `lib:SetCogProfile`, `lib:GetCogSetting(cog, key)`, `lib:GetCogTheme(cog)`. (#22)
- **Per-cog font resolution** — `lib:GetFont(key, cogName?)` returns a cog-specific FontObject when that cog has an active override; untagged calls keep returning the suite-active fonts (back-compat). The font set is rebuilt lazily via `lib:_RefreshCogFonts(cog)` on profile switch. (#22)
- **`lib:CreateUIScalingSettingsBlock(parent, opts)`** (`Cogworks-1.0/Scaling.lua`) — drop-in section for any cog's settings page. Profile dropdown with `[+ New] [Export] [Import]`, font/UI scale sliders, font family + theme dropdowns, reset button, and a per-cog override row when `opts.cog` is provided. Reflects external `SettingsChanged` events. (#18)
- **`lib:RegisterScalingFrame(frame, opts)`** — subscribes a frame to `SettingsChanged` for `uiScale` so `SetScale` fires automatically. Optionally persists `{x, y, w, h}` into a caller-owned SV table on `OnDragStop` / `OnSizeChanged`. (#18)
- **`lib:CreateSegmentedControl(parent, opts)`** (`Cogworks-1.0/SegmentedControl.lua`) — horizontal pill-button group with one-active invariant. Sizes `small` / `normal` / `large`. Auto-widths each pill from its label + padding; reflows on `SettingsChanged` for fontScale/fontFamily. Distinct from `CreateTabPanel` (which owns content swap) and `CreateNavButton` (sidebar shape). (#19)
- **`lib:CreateSettingsInput` validate + suffix + Flash** (`Cogworks-1.0/Forms.lua`, MODULE_MINOR 14 → 15) — three additive opts: `validate(value) -> ok, errMsg` reverts and red-flashes on failure; `suffix` renders a dim "hours" / "%" label right of the input; `row:Flash(errMsg)` exposes the same flash for backend-side rejections. Returned row also has `GetSuffix` / `SetSuffix`. (#20)
- **`lib:CreateSectionHeader` opts-table form** — second arg can now be `{ text, rule, anchor = {frame, point}, gap, color }`. `rule = true` adds a 1px theme.border underline; `anchor` lets sections cascade off siblings instead of always anchoring TOPLEFT to the parent. Legacy positional `(parent, "TEXT", -8)` keeps working unchanged. (#21)

### Fixed

- **`Tree` and `ReorderableList` rows render full-width** (MODULE_MINOR 15 → 16 each). The scroll content frame was hardcoded to width 1; rows anchored TOPRIGHT to content ended up 1px wide, leaving them with no clickable area and an invisible backdrop. Both modules now hook the scroll's `OnSizeChanged` to keep `content:SetWidth` in lockstep with the viewport.
- **`MiniView` close + pin buttons are visible** (MODULE_MINOR 15 → 16). Replaced the 16px `UI-Panel-MinimizeButton-Up` close glyph (mostly transparent at that size) with the standard `UIPanelCloseButton` template at 20px, and switched the pin to `LockButton-{Locked,Unlocked}-Up` so the locked / unlocked state reads at a glance.
- **`ReorderableList` rows are draggable** (MODULE_MINOR 16). Two latent bugs: (1) `row:StartMoving()` silently no-ops without `SetMovable(true)`, so the row state changed on drag but the frame stayed put — added `SetMovable(true)` in `acquireRow`. (2) `OnDragStop` calling `refresh()` triggers `releaseRow → Hide` on the still-being-dragged row, and `Hide` on a dragged frame re-fires `OnDragStop`; the second pass tried to index the now-nil `dragging` upvalue. Added a re-entrancy guard at the top of `OnDragStop`.
- **Standalone showcase sidebar nav no longer overflows**. The 16 `CreateNavButton` rows ×32 px each ran past the ~448 px sidebar even at 1.0× scale; at 1.4× the bottom four pages were unreachable. Wrapped the nav stack in a `ScrollFrame` with mouse-wheel scrolling so any number of pages stays accessible regardless of font/UI scale. Also bounded `CreateNavButton`'s label with a RIGHT anchor and `SetWordWrap(false)` so longer labels (e.g. "Reorderable") clip cleanly at the button edge instead of extending past the sidebar at high font scales.

### Notes

- The shared SV requires every consumer cog's TOC to declare `## SavedVariables: CogworksSharedDB`. Cogs that haven't yet adopted the declaration will continue to work, but their session will run with in-memory settings only — exactly the same behavior as before this release.

## [0.11.0] — Phase A/B/C UI primitive set

Bumps MINOR from `12` to `15`. The full primitive set called for in cogworks issue #1 — the FlipQueue migration toolkit, plus Tempo / Maxcraft / Tally rebuilds. Per-module load guards landed in this release so older vendored copies in sibling cogs no longer clobber newer methods.

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
