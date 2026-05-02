# Session handoff — 2026-05-02

Snapshot for the next agent picking up Cogworks work. Read this first.

## Where we are

**v0.13.0 shipped end-to-end on 2026-05-02.** Tag `v0.13.0` (commit `17240a7`) is on `origin/main`; BigWigsMods packager workflow ran `success`; live on CurseForge + Wago.

This session's two releases:

| Tag | Date | Headline |
|---|---|---|
| `v0.12.0` | 2026-05-01 | Suite settings persistence (`CogworksSharedDB` + profiles + per-cog override) + Phase D primitive batch (UI scaling block, segmented control, settings input validate/suffix/Flash, section header opts-form) |
| `v0.13.0` | 2026-05-02 | Debug toolkit + ThemedMainFrame + Drawer + Slash registry + Toast + standalone gear-bordered minimap button + mesh-spin easter egg |

Lib MINOR is now `17`. `lib.version = "0.13.0"`.

## What's actually in the lib now (v0.13.0)

Full primitive set; sibling cogs can adopt without reimplementing:

- **Persistence/profiles**: `CogworksSharedDB`, profile API (`Get/Set/Create/Delete/Rename/Export/ImportProfile`), per-cog override (`Get/SetCogProfile`, `GetCogSetting`, `_RefreshCogFonts`, `GetFont(key, cogName?)`)
- **Main window chrome**: `CreateThemedMainFrame` — title + summary + sidebar + content + resize + ESC + persisted geometry; `AddNavItem`, `SetActivePage`, `SetSummary`, `SetPageBuilder`
- **Floating panels**: `CreateDrawer` (non-modal), `CreateMiniView` (heads-up), `CreatePopup` (modal)
- **Slash commands**: `RegisterSlashCommands(addonName, opts)` — globals + dispatch + auto-help; `AddSlashCommand` for late registration
- **Alerts**: `Toast(opts)` — fade-in/out, vertical stacking, severity → theme color, click-to-dismiss
- **Debug toolkit**: `RegisterDebugLogger`, `RegisterDebugInspector`, `RegisterDebugAction`, `Profile(cog, label, fn)` (zero overhead when disabled), `DumpDebugState`, `SerializeDebugValue`, `CreateDebugConsole` (tabbed dashboard), `CreateCopyDialog`. `LibDebug` event auto-bridges lib-internal events into every cog's logger.
- **Settings UI**: `CreateUIScalingSettingsBlock`, `RegisterScalingFrame`, `CreateSegmentedControl`, `CreateSettingsCheckbox/Button/Input` (input has `validate`, `suffix`, `Flash`)
- **Phase A/B/C primitives** (still here from v0.11): `CreateTabPanel`, `CreateWizard`, `CreateTree`, `CreateReorderableList`, rich-text helpers in `Text.lua`, etc.
- **Section header opts form**: `CreateSectionHeader(parent, { text, rule, anchor, gap, color })` — legacy positional still works
- **Minimap button helpers**: `RegisterCogMinimapButton` now wires the mesh-spin easter egg automatically (hover any cog button → others briefly spin)

Showcase pages exist for every primitive at `/cogworks ui` (21 pages including v0.13's Debug/MainFrame/Drawer/Toast/Slash).

## What's next — by priority

### 1. FlipQueue adoption (the actual point of all this)

User explicitly said "I would like 15/16/17 included as well, we need to get the full set of primitives so I can move FQ to starting to use everything." Cogworks has now delivered everything FlipQueue's UI/UX rebuild was waiting on.

Adoption work happens in the **flipqueue** repo (`C:/src/flipqueue`), not here. Migration plan lives at `docs/migration/flipqueue.md` (written in v0.11 era; will need refreshing to call out the v0.12/v0.13 additions). Likely first targets per the existing plan:

1. **FQ #18** — font/scale settings (player ask). Now even better: use the new `CreateUIScalingSettingsBlock` for one-call settings page; profile system covers per-character font overrides.
2. **FQ #14** — MainFrame migration. **Now uses `CreateThemedMainFrame`** instead of hand-rolled chrome (~300 LOC win).
3. **FQ #15** — drawers + popup migration. **`CreateDrawer` is the right primitive** for `ToolDrawer.lua`, `ContextDrawer.lua`, `BankPopup.lua`, `ExportPopup.lua` (replaces ~600 LOC of duplicated chrome).
4. **FQ slash dispatcher** — `UI/SlashCommands.lua` (1152 LOC) → `cw:RegisterSlashCommands` (~150 LOC of pure boilerplate goes away; command bodies stay).
5. **FQ debug surface** — replace `UI/DebugConsole.lua` + `ns:PrintDebug` + `ns._debugLog` with `cw:RegisterDebugLogger("FlipQueue", ...)` + `cw:CreateDebugConsole`. `DebugPage.lua` and `LogPage.lua` stay FQ-specific (domain data).
6. **FQ chat-noise toasts** — `~20 ns:Print` calls for "Posted X items", "Scan complete", "Sale logged" should become `cw:Toast` instead of chat spam.

Pre-req: bump FlipQueue's `.pkgmeta` `Libs/Cogworks-1.0` external `tag:` from `v0.12.0` to `v0.13.0`. (Per project memory it was on `v0.10.0` at start-of-session; user updated to `v0.12.0` mid-session for the v0.12 adoption pass.)

### 2. Remaining open Cogworks issues

| # | Title | Status / next step |
|---|---|---|
| 1 | UI primitive buildout (meta-tracker) | All requested primitives now shipped. Re-evaluate for closure once FQ has actually adopted them. |
| 2 | Cross-realm key extraction & hardening | Partial. `Realms.lua` has normalization + matching; still pending: connected-realm graph, TSM key parser, server-time helpers. |
| 12 | Minimap-rim cluster widget | Design-question stub. Possibly already covered by `CreateGearAssembly` — needs body re-read to confirm. |
| 23 | CreateProgressBar / chunked-task widget | `CreateProgressBar` exists; the **chunked-iterator + auto-progress wrapper** is the new ask. Useful for Tally net-worth recompute, Maxcraft recipe scan, FQ AH parse. Probably v0.14. |

### 3. Sibling-cog TOC pickups

Per the v0.12 changelog note: every consumer cog needs `## SavedVariables: CogworksSharedDB` in its TOC to get persistence. Adoption status unknown across **Tempo**, **Maxcraft**, **Tally** — until they declare it, those cogs run with in-memory settings only.

## Known follow-ups (not scheduled)

- **User declined** the offer to schedule a 2-week check-in agent — they'll handle FQ adoption tracking themselves.
- **`docs/migration/flipqueue.md`** is written for the v0.11 primitive set. It should be refreshed once FQ starts actually adopting v0.12/v0.13 primitives, but defer until adoption is in motion (the plan reflects the user's discoveries, not pre-planned design).
- **Lib upgrades for vendored LDB / LDBIcon** are now manual (see `.pkgmeta` comment). When LibDataBroker-1.1 or LibDBIcon-1.0 cuts a new version that matters, refresh the `Libs/` copies and commit.

## Project state at handoff

- Branch: `main`, clean working tree, fully pushed
- Last commit: `17240a7 fix(pkgmeta): vendor LDB + LDBIcon directly, drop wowace SVN externals`
- Last release: `v0.13.0` (success, live on CF + Wago)
- All v0.12 + v0.13-resolved issues commented + closed (#14, #15, #16, #17, #18, #19, #20, #21, #22, #24)

## Operational reminders

- **Never auto-tag/push without explicit user go-ahead** (live-user constraint memory). Tag-push is what fires the release pipeline → CurseForge/Wago.
- **`.pkgmeta` externals only resolve at packaging time.** Anything required for local dev needs to be vendored under `Libs/`. The wowace SVN host is flaky — prefer vendoring over externals for new libs.
- **Per-module `MODULE_MINOR` guards** must be bumped any time a module file's behavior changes, otherwise older sibling-cog vendored copies will skip the load and clobber the newer methods.
- **Cogworks audience is integrators, not players** — `CHANGELOG.md` engineering prose is appropriate; no `## Player summary` blocks required for issue close-outs.
