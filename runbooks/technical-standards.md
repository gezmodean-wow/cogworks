# Technical standards


Technical conventions that apply across every cog. The vast majority of code in the suite is written by agents (Claude in particular); these rules optimize for two things:

1. **Outside contribution** — a player or community contributor should be able to read the code, understand it, and submit a PR without an onboarding call.
2. **Parallel agent work** — multiple agents working in the suite simultaneously should not step on each other or lose context across session boundaries.

Where this runbook **overrides** default agent behavior (e.g. Claude's default "no comments" rule), the override is called out explicitly so an agent reading this knows to apply project rules over their built-in defaults.

## Standards changelog

Sessions check the top entry below against their `CLAUDE.md` "Last acknowledged" code for this runbook. If newer, prefix the first response with `Standards updated:` plus a one-line summary per new entry, then update the cog's acknowledged code.

- **2026-05-05a** — Initial codification. Twelve sections: comments + readability, license compliance, smaller files, agent handoff, backwards compatibility, debug surface (uniform adoption of cogworks debug toolkit), naming hygiene, performance, **localization** (new), **SV size discipline** (new — constant-pool cap, blob storage default for growable data), **TOC interface-version policy** (new — multi-TOC at patch day, drop legacy on next release), **cogworks-driven UI primitives** (new).

## 1. Code is commented and human-readable

**Overrides default "no comments" rule.** Project goal is outside-contributor legibility. Comments augment naming; they don't replace it.

- **File-level headers.** Every Lua file starts with a short comment block: what this module does, what other modules it depends on, any non-obvious lifecycle (event subscriptions, timing constraints).
- **Function-level intent comments.** Non-trivial functions get a short comment explaining intent — especially when the function name alone doesn't capture *why* it exists vs. an adjacent function. Parameters and returns documented when not obvious from naming.
- **Inline comments for non-obvious choices.** Workarounds for specific bugs, hidden constraints, why a path was chosen over an alternative, references to ticket IDs that explain the history. Cite file:line references where a comment in one file relates to behavior in another.
- **WoW API gotchas referenced when present.** If the code is structured around a Blizzard quirk (e.g. "C_Container.UseContainerItem fires from non-secure context unless…"), say so.
- **Comments must be kept current.** A stale comment is worse than no comment — it actively misleads. Update or delete on change.
- **Naming still does the heavy lifting.** Comments explain WHY; well-named functions and variables explain WHAT. A comment that just restates the function name is noise.

Look at existing files for the established voice: `flipqueue/.pkgmeta`, `cogworks/.github/workflows/verify-package.yml`, and `tally/CHANGELOG.md` carry the project's commenting tone — explicit, contextual, citing the bug or ticket that motivated the design.

## 2. License compliance

Every vendored library, third-party GitHub Action, externally-sourced code pattern, or referenced research must have its license verified before merge.

**Compatible licenses** (safe to use in the addon ecosystem):
- MIT, BSD (2-clause / 3-clause), zlib, Apache 2.0
- Public domain / CC0
- WoW addon community licenses (most addons are MIT or similar)

**Incompatible without explicit clearance:**
- GPL / AGPL / LGPL — copyleft license, would impose its terms on anything linking to it. The WoW addon ecosystem is generally MIT-style; mixing in GPL forces the whole project to GPL.
- Proprietary / no-license — "no license" defaults to "all rights reserved" in copyright law; do not vendor or copy.

**Specific cases:**
- **Vendored libs** in `.pkgmeta` externals (Cogworks-1.0, LibSerialize, LibDeflate, etc.) — license checked before bumping; license text travels with the lib (LibStub / Ace3 conventions).
- **GitHub Actions** — `BigWigsMods/packager`, `actions/checkout`, `peter-evans/create-pull-request`, `ncipollo/release-action` are all in current use and verified. Pin to major version (or full SHA for paranoid mode).
- **Code patterns researched online** — fine to learn from a Stack Overflow / blog / forum answer; do *not* paste verbatim without checking the source's license. Cite the source in a comment for non-trivial adaptations.
- **Blizzard UI source** — publicly available but not freely licensed. Referencing patterns and API usage is fine (you can't copyright how an API is called); copying chunks of Blizzard's code is not.
- **AI-generated code** — agents do not introduce code that resembles copyrighted sources without provenance. If output looks like it came from somewhere identifiable, agents must declare so before committing.

**On introduction:** the CHANGELOG entry that adds a new vendored lib or referenced pattern cites the license and source. Example from existing tally CHANGELOG: `Libs/LibSerialize/LibSerialize.lua (MIT, v5, by Ross Nichols)`.

**Repo-level:** every cog has a `LICENSE` file. Suite default is MIT unless a specific cog has a different choice on file.

## 3. Smaller files preferred

Soft cap: roughly 500–1000 lines per file. The exact number isn't load-bearing; the rule is **prefer splitting when a logical seam exists**.

**Rationale.** Two agents working on the same large file collide on merge. Two agents working on adjacent small files don't. The vast majority of code being agent-written makes this the deciding factor for parallelizability.

**Practical rules:**
- New files are cheap. When adding functionality that has its own logical boundary, prefer a new file in `Modules/` or a sibling directory over stuffing into an existing file.
- When working on an existing file that's already over the soft cap, prefer to add the new logic in a new file rather than inflating further.
- If a file is genuinely *over* the cap and the work calls for it, propose a refactor split as a separate `chore/` PR — don't bundle the split with the feature change.
- **Counter-rule:** don't fragment for fragmentation's sake. One-function-per-file is its own pathology. Split where there's a real boundary (a feature, a subsystem, a dispatch table, a UI panel).
- Some files are intrinsically large: central dispatch (`Core.lua`), saved-variable schema modules, the cog's main entry. Acceptable to be over cap if the alternative is artificial splitting.

**When evaluating:** if you're scrolling through a file looking for "the right area," it's probably too big. If you're jumping between two files for a single change, they're probably split too granularly.

## 4. Agent handoff discipline

The vast majority of code is agent-written; agent context does not survive across sessions by default. Cross-session continuity is mandatory.

**Per-issue status comments.** When an agent stops working on an issue (whether complete, blocked, or deferred), it leaves a comment capturing:
- What was actually attempted (concrete: "looked at `BankQueue:Process`, traced the path through `IssueOne`, saw that…").
- What was tried that didn't work, with reason.
- What the current best understanding is.
- Concrete next step if any.

A comment that just says "WIP" or "still looking" is not enough — it gives the next agent nothing to start from.

**Cross-session followups.** Items that span sessions but aren't yet a ticket go into `chronoforge/.../memory/pending_followups.md`. Date-stamped, brief, with the trigger that should reactivate them. Existing pattern: "2026-05-04: update chronoforge CLAUDE.md w/ CF-N + meta-ticket home; triage tempo#2 + maxcraft#2 before driving CF-3."

**PR drafts get a "Resume context" section.** If a PR is left as draft for any reason, the description includes a short "Resume context" block explaining where the work stands and what the next agent should do to continue.

**Branch naming is descriptive.** `fix/bag-taint-batched-process` not `fix/issue` or `fix/bug`. Another agent should be able to identify what a branch is about from its name alone, without reading commits.

**Commit messages document failed approaches when relevant.** "Tried X first, but Y because Z" is information another agent can act on. Don't pretend the work was a straight line if it wasn't.

**Stale-issue triage.** Issues with no comment activity in 30+ days get a status check by a coordinator-mode agent: still relevant? Re-state the current understanding, or close with reason.

## 5. Backwards compatibility for player-visible state

Players have data, muscle memory, and configuration. Breaking these silently is the worst outcome.

**Saved-variable schemas.** Every cog's SV table carries a version number (e.g. `TallyDB.schemaVersion`). Breaking changes require:
- A migration function that runs on `ADDON_LOADED` (or earliest viable point) when the on-disk version is older than the current.
- Forward-only by default — once migrated, the SV is the new version. No automatic downgrades.
- Migration tested on a real on-disk SV before merge, not just on synthetic data.

**Slash commands.** Removed slash commands keep working as deprecated aliases for at least one minor release, with a one-time chat message pointing the player at the new command. Never silently no-op.

**Settings removals.** A removed setting either:
- Auto-migrates its value into a new setting / data structure (preferred), OR
- Prints a one-time chat message explaining what changed and where the new control is.

**Cogworks-1.0 is additive only.** This is an existing established rule (see cogworks CHANGELOG.md header). Concretely: never remove an API method. Deprecate via `### Deprecated` in the CHANGELOG, keep the method functional, remove only on a MAJOR version (`vN.0.0`) — and the suite hasn't reached `v1.0` yet, so removal is essentially never on the table for v0.x.

**Cog public APIs.** Functions on the cog's namespace table (`ns.<something>`) are more flexible — addons aren't libraries, and there are no external consumers. Still: if a cog depends on another cog's public API (rare), treat that boundary like a library API.

## 6. Debug surface and observability

The goal is **shareable diagnostics**: players hitting a bug should be able to capture and forward the cog's state in one action; agents triaging the report should see predictable structure regardless of which cog produced it. Errors not being silent is one component of this; the larger frame is "every cog presents a consistent debug surface that doesn't depend on a player who can copy chat or remember slash commands."

This rule **overrides** Claude's default "don't add diagnostic plumbing speculatively" — diagnostic plumbing is required infrastructure here, not nice-to-have.

The user-facing surface is **cogworks's debug toolkit**, already shipped in `Cogworks-1.0/Debug.lua` (added in v0.13.0). The primitives:

- `lib:RegisterDebugLogger(cog, opts)` — per-cog ring-buffer log object
- `lib:CreateDebugConsole(opts)` — tabbed UI window (Actions / Inspectors / Profile / Log)
- `lib:RegisterDebugInspector(cog, name, fn)` — register a named state accessor
- `lib:RegisterDebugAction(cog, label, fn)` — register a button on the console
- `lib:CreateCopyDialog(text, hint?)` — modal popup with copy-friendly EditBox + Ctrl+A/C
- `lib:DumpDebugState(cog)` — concatenate all inspectors into one copy-friendly blob
- `lib:Profile(cog, label, fn, ...)` — wrap a call with `debugprofilestop` timing
- `LibDebug` event bridge — lib internals auto-flow into every cog's logger, tagged `[Cogworks-1.0/<scope>]`

The standard is **uniform adoption** across every cog. No cog-local debug plumbing.

### 6.1 Minimum viable debug surface

Every shipping cog must register the following.

**Slash entry point.** `/<cog> debug` opens (toggles) a `CreateDebugConsole({ cog = "<Cog>" })`. Cogworks itself uses `/cogworks debug`; all consumer cogs follow the same pattern.

**About-page surface** (where the cog has one — flipqueue + tally do, others should). A "Copy diagnostics" button on the About page calls `lib:DumpDebugState(cog)` and routes the result into a `CreateCopyDialog`. Player-facing entry that doesn't require opening the debug console at all.

**Required Inspectors** (every cog registers these — agents triaging a bug know they exist):

| Inspector | Returns |
|---|---|
| `version` | addon version + embedded Cogworks-1.0 version + WoW build |
| `settings` | current settings table, sanitized of player-private data (account/char names if not relevant to the diagnostic) |
| `state` | high-level cog state — "loaded: yes, libs: yes, N entries in DB, last save: <timestamp>" |

Cog-specific inspectors layer on top: tally has `Storage`, flipqueue has `BankQueue` / `Schema`, etc. These follow the same shape (table return value, structured fields).

**Required Actions** (buttons on the console's Actions tab):

| Action | Behavior |
|---|---|
| `Copy diagnostics` | `lib:DumpDebugState(cog)` → `CreateCopyDialog` |
| `Toggle debug` | flip the cog's Logger `enabled` flag |
| `Clear log` | clear the Logger ring buffer |

Cog-specific Actions layer on top — "Reset bag-taint state" (flipqueue), "Force backfill from TSM" (tally), etc.

### 6.2 All debug output flows through the Logger

No `print()` calls for debug output. Use `Logger:PrintDebug(...)` (the object returned from `lib:RegisterDebugLogger`).

Why this matters:
- Output appears in the Console's Log tab automatically.
- Toggleable via `Toggle debug` without rebuilding.
- Survives in the ring buffer (default 500 entries) for retroactive triage — the player doesn't have to be looking at chat at the right moment.
- Subscribable via `Logger:OnAppend(cb)` for live consoles or future log-to-file behavior.
- The `LibDebug` bridge auto-merges Cogworks-1.0 internal activity into the same log.

`print()` is reserved for **intentional player-facing chat output** — setup-completed acknowledgements, error messages a player needs to see *now*, etc. If in doubt, it's debug; use the Logger.

### 6.3 Error context flows into the Logger

The old "no silent failures" content lives here as a sub-rule.

**`pcall` discipline.**
- Every `pcall` (or `xpcall`) that fails logs to the cog's Logger with enough context to triage: which function, which input shape, which path.
- Don't `pcall` to "make warnings go away" — if a failure is expected and tolerable, comment *why* in the call site; if it's a real signal, log it.

**Returns and nil semantics.**
- Don't `return nil` in a path where the caller can't distinguish "no result" from "error." Use `nil, err` or a sentinel.
- Functions whose only error mode is "no result found" can return nil; document it in the function header comment.

**Error strings include enough context** that a player pasting them into a bug report gives the agent something to act on. Not "Failed to parse"; rather "Failed to parse gold value '<input>' (locale: deDE)".

Use `error()` for programmer errors that should never happen in production (assert-like). Use logged warnings for runtime conditions that recover gracefully.

### 6.4 Long output → CopyDialog, not chat

Anything more than ~3 lines of debug output uses `lib:CreateCopyDialog`. Chat is for player-facing one-liners and acknowledgements; CopyDialog is for forwarding state to a developer.

This addresses two real player constraints:
- Not every player has a UI setup that lets them copy from chat (some chat addons strip selection; mouse-over chat is fiddly).
- Long output scrolls past the chat history before a player can read it.

Tally already migrated `/tally diag` from chat-default to copy-dialog-default in alpha10 — that's the canonical pattern.

### 6.5 Diagnostic commands surface as Actions, not just slash sub-commands

Every diagnostic worth running by a player is a button on the debug console's Actions tab (registered via `lib:RegisterDebugAction`), *not just* a memorized slash sub-command.

Slash sub-commands stay as power-user aliases (`/tally diag divergence`, `/fq debug parsegold`, etc.) — they're fast for someone who already knows the command. But the **discoverable** surface is the console's Actions tab.

Why: not every player can copy chat. Not every player remembers a 4-word slash command. Buttons in a window solve both.

### 6.6 Established patterns to lean on

Three patterns from existing cogs generalize and should be the first reach when adding new diagnostic surface:

- **Skip counters** (tally `/tally diag` SkipCounters) — every adapter row that fails to land in the ledger increments a labeled counter (`bad_item_key`, `invoice_no_item_id`, etc.). Surfaced as an inspector. Lets testers self-report what's missing without you having to ask "did you see X?".
- **Profile counters** (tally `Storage` inspector — `serialiseMs / compressMs`) — wrap perf-critical paths with `lib:Profile` (or raw `debugprofilestop`) and surface the timing in an inspector. Lets testers verify a perf fix without external tooling. The TLY-50 logout-perf hotfix is the canonical example.
- **Structured inspector outputs** — inspectors return tables that `lib:SerializeDebugValue` knows how to render. Don't render to strings inside the inspector; let the toolkit format. Easier to copy, easier to grep, easier to evolve.

### 6.7 Bug-report integration

The bug-issue template (`templates/bug-issue.md`) asks for "the output of `Copy diagnostics`" as part of the Environment / Additional Context section. The scribe Discord→GitHub bridge should pre-fill this ask in mirrored issue bodies (separate work; tracked separately).

When a report comes in without diagnostics:
1. Triaging agent's first response is to ask for it: "Please run `/<cog> debug` → click `Copy diagnostics` → paste the result into a comment."
2. Or, for a tester with a known reproduction path, the agent can guide them: "Open Settings → About → Copy diagnostics."

Standardizing on `Copy diagnostics` as *the* phrase players hear means muscle memory builds across the suite, not per-cog.

### Cogworks-side responsibilities

Cogworks's role in this:
- **Maintain the Debug toolkit** as the source of truth — additions to the API land in cogworks first, downstream cogs consume on bump.
- **Document the toolkit** (`Cogworks-1.0/Debug.lua` header comment + cogworks CHANGELOG `### Added` entries when surface grows).
- **Test against its own standalone install** — every Debug API addition is exercised by `/cogworks debug` before downstream is asked to adopt. (Cogworks runs the toolkit against itself; this is meta-validation that the API works.)

When a cog adds a new pattern that should be lifted to suite-wide use (e.g. tally's profile counters in TLY-50 leading to a `lib:Profile` API in cogworks v0.13.0), file it as a cogworks ticket and migrate the cog's local impl to the cogworks-provided API once shipped.

## 7. Naming and namespace hygiene (cross-cog only)

Per-cog conventions live in each cog's CLAUDE.md. The following apply suite-wide:

- **Slash commands prefix with the cog name.** `/tally`, `/fq`, `/tempo`, `/mxc`, `/cogworks`. No `/q` for FlipQueue; no name collision pressure.
- **No leaking globals.** Every Lua file uses the `local addonName, ns = ...` pattern at the top. Functions and tables hang off `ns`. Never write a bare `function Foo()` or `Foo = {}` at module scope.
- **Saved variables follow `<CogName>DB` (account) / `<CogName>CharDB` (per-character).** Migrations of SV names are breaking changes (rule 5).
- **Cogworks library APIs:** `lib:CamelCase` for public, `lib:_camelCase` for internal. Internal APIs are not stable across MINOR bumps.
- **Module guards in vendored libs:** `MODULE_MINOR` increments per file when its content changes. Cogworks's pattern is the reference — see `Cogworks-1.0/Scaling.lua` MODULE_MINOR `1 → 2` in COG-30.

## 8. Performance discipline (light, expandable per cog)

Cross-cog defaults; per-cog CLAUDE.md may add specifics.

- **Hot-path locals.** In any loop or frequently-called function, hoist table accesses to locals at function top. `local Process = self.Process; for ... do Process(self, ...) end` over `for ... do self:Process(...) end` if the call shape lets you.
- **`debugprofilestop` for perf-critical paths.** Wrap save/load, large-data passes, and frame handlers when there's any reason to measure. Surface the measurement somewhere observable (`/cog diag` is the cog idiom — see `tally/Ledger.lua` `serialiseMs/compressMs` for the established shape).
- **Avoid table allocation in inner loops.** Reuse pre-allocated tables; clear and refill rather than create-and-discard.
- **Batch large-data work across frames.** Anything processing more than ~1000 entries blocks the frame; use `C_Timer.After(0, fn)` or a coroutine to batch. FlipQueue's import-pipeline chunking (FQ-131) is the established pattern.
- **Don't optimize speculatively.** Measure first. The above rules are about not making the obvious mistakes; they aren't a license to micro-optimize cold paths.

## 9. Localization

The chronoforge player base includes many non-native English speakers; localization is a hard requirement, not nice-to-have. The mechanism uses a cogworks-provided primitive plus the WoW addon ecosystem's standard tooling.

**Cogworks-side primitive** (not yet shipped — file as cogworks ticket as part of adoption):

```lua
-- Cogworks-1.0/Locale.lua (proposed)
local L = lib:CreateLocaleTable(addonName, "enUS")  -- default locale
L:Register("enUS", { ["DEPOSIT_TASKS"] = "Deposit Tasks", ... })
L:Register("deDE", { ["DEPOSIT_TASKS"] = "Aufgaben einzahlen", ... })

-- Lookup: L["DEPOSIT_TASKS"] returns the active-locale string,
-- falls back to enUS if missing, returns "[KEY]" if missing both.
-- L:GetCoverage() reports per-locale completeness for the debug Inspector.
```

**Per-cog requirements:**

- `Locales/` directory with `<locale>.lua` per supported language (`enUS.lua` default; `deDE.lua`, `frFR.lua`, `esES.lua`, `ruRU.lua`, `koKR.lua`, `zhCN.lua`, `zhTW.lua`, `ptBR.lua`, `itIT.lua` as community translations land).
- All player-facing strings (UI text, chat output, error messages, slash command help) go through `L["KEY"]` lookups. No inline literals for player-facing text.
- Keys named in SCREAMING_SNAKE_CASE describing intent (`DEPOSIT_TASKS`, `BANK_OPENED`), not by source-language wording.
- `Locales/Locales.xml` references each per-locale file; loaded after Cogworks-1.0 in the TOC.
- A `localization` Inspector registered on the debug console reports active locale + per-locale missing-key count.

**Translation tooling:**

- BigWigsMods packager supports `@localization(locale="...", key="...")@` substitution at package time, fed by CurseForge's localization import. Each cog opts in via TOC `## X-Localization-Key` config. This is the standard WoW addon path — no custom infrastructure on our side.
- enUS strings hand-maintained in the cog repo. Other locales pulled from CurseForge's translation tool by the packager.

**Migration path per cog** (file as per-cog ticket after primitive ships):

1. Audit player-facing string literals (`grep -rE '(SetText|print|format)\("' **/*.lua`).
2. Move to `Locales/enUS.lua` keyed by SCREAMING_SNAKE_CASE.
3. Replace literals with `L["KEY"]`.
4. Ship enUS-only first; community translations follow once keys are stable.
5. **Don't rename keys retroactively** — once a key is published, its meaning is stable. New variants get new keys.

**Adoption gate:** localization rollout is gated on cogworks shipping `lib:CreateLocaleTable`. File as cogworks ticket; per-cog migration tickets follow once primitive ships.

## 10. Saved-variable size discipline

WoW writes each addon's saved variables as a Lua chunk. Lua's per-chunk constant-pool cap is **2^18 (262,144) entries**. More distinct constants than that → the file fails to load wholesale, the addon thinks the player is fresh-installed every session. Tally hit this in TLY-49 with ~91k+ ledger rows × multiple distinct fields per row.

**Mitigation pattern: compressed blob storage** (LibSerialize + LibDeflate). The data structure becomes one Lua constant in the SV chunk regardless of entry count. See tally's `Ledger.lua` for the canonical implementation.

**Rules:**

- **Cogs with growable data structures** (ledgers, queues, history, capture buffers) MUST plan for the constant-pool cap. Default to compressed blob storage.
- **Cogs with bounded data** (settings, feature flags, fixed config) stay raw — they'll never approach the cap.
- **Required Inspector: `SV`** — reports entry counts, blob byte size, dirty flag, save-time profiling. Warning marker when within 50% of interim limits (see below). Tally's existing `Storage` inspector is the reference shape.

**Cogworks ticket: lift tally's blob storage into a primitive.** `lib:CreateBlobStorage(name, schemaVersion)` returning a working-memory wrapper that lazy-loads from blob, saves on dirty, instruments serialise/compress timing. Every cog gets the pattern for free.

**Conservative interim limits** (pending empirical research):
- Single-chunk SV (no blob): keep distinct constants below 100k. The `SV` Inspector reports current count.
- Blob SV: keep file size below 5 MB on disk. (Tally blob ledgers in production sit well under this.)

**Action item — empirical research** (file as coordinator ticket): test SV file sizes vs. load times across realistic content shapes (numeric-heavy ledger, string-heavy settings, mixed). Set concrete byte/entry numbers from measurement; replace the conservative interim limits above. Until that research lands, the 100k / 5 MB defaults stand.

## 11. TOC interface-version policy

Goal: zero downtime for players when WoW patches.

**At a WoW patch:**
- The cog release that lands the new patch ships with **multi-TOC** — both the legacy interface number and the new one. BigWigsMods packager handles multi-TOC via either multiple values on `## Interface:` lines or per-flavor `<addon>_Mainline.toc` / `<addon>_Vanilla.toc` / `<addon>_Cata.toc` files (whichever the cog already uses).
- Tag this release at the patch-day version (e.g. `v0.13.0` if WoW 11.X.0 ships that day).
- CHANGELOG entry notes the multi-TOC support: "Supports both WoW <old> and WoW <new>; legacy support drops in the next release."

**Next release after the patch:**
- Drop the legacy interface number. Single forward-only TOC for the new WoW version.
- CHANGELOG entry includes a deprecation note: "Drops support for WoW <old version>; players must update WoW to keep using <cog>."

**Coordination:**
- Pre-patch: track the WoW patch calendar. The suite-wide bump usually happens together (one minor bump across all cogs around patch day). Until a coordinator runbook tracks this, the user calls the timing.
- Cogworks bumps first (since cogs vendor it). Consumers bump their `.pkgmeta` Cogworks pin and their TOC interface in one PR per cog.

## 12. Cogworks-driven UI primitives

Cogworks-1.0 owns settings UI primitives and other cross-cog UI surfaces. Currently shipping (per cogworks CHANGELOG v0.13.0):

- `lib:CreateUIScalingSettingsBlock(parent, opts)` — drop-in scaling settings section
- `lib:CreateSegmentedControl(parent, opts)` — pill-button group, one-active invariant
- `lib:CreateSettingsInput` — text/number input with `validate` / `suffix` / `Flash`
- `lib:CreateSectionHeader` — section header with optional rule + custom anchor
- `lib:CreateThemedMainFrame(opts)` — main window chrome (title bar, sidebar, content area)
- `lib:CreateDrawer(opts)` — non-modal floating panel
- `lib:CreatePopup` / `lib:ShowConfirmDialog` — modal popups
- `lib:Toast(opts)` — transient banners
- `lib:CreateMiniView` — heads-up panel
- `lib:CreateCopyDialog` — copy-friendly modal (also used by the debug toolkit)
- `lib:RegisterScalingFrame(frame, opts)` — auto-rescale on `SettingsChanged.uiScale`

**Rules:**

- **No cog-local settings widgets if a cogworks primitive exists.** If you find yourself rolling a slider, dropdown, or input field with custom styling, stop. Either the primitive exists and you use it, or it doesn't and the right move is to add it to cogworks (file a cogworks ticket; ship the primitive; downstream cog adopts).
- **Settings page layout follows the established pattern**: General → feature groups → meta controls. Tally and FlipQueue's settings pages are the reference. Use `CreateSectionHeader` between groups; group-master switches as `CreateSegmentedControl` or labeled toggles.
- **Theming and font-scale honor cogworks's `SettingsChanged` events.** Don't wire `frame:SetScale` or font sizes manually — use `lib:RegisterScalingFrame(frame, opts)` so the cog reflows when a player adjusts UI scale or font.
- **New patterns lift to cogworks before being used widely.** If a single cog needs a one-off widget, rolling it locally is fine — but if a second cog wants the same thing, that's the signal to file a cogworks ticket and lift the primitive.

This rule applies to **settings UI and chrome** specifically — that's where suite-wide consistency matters most for players. Cog-specific feature UI (FlipQueue's queue table, Tally's ledger table) can roll its own; those are core feature surfaces, not shared chrome.

## How this runbook interacts with others

- **Branch and release flow** (`branch-and-release-flow.md`) — when these rules trigger work (e.g. a license issue forces a removal), the work flows through the standard branch / PR / release cycle.
- **Doc conventions** (`doc-conventions.md`) — license citations land in CHANGELOG entries (rule 2 + G2).
- **Comms conventions** (`comms-conventions.md`) — the `## Player summary` rule for issue bodies is what populates RELEASES.md and Discord announcements; the `Copy diagnostics` ask in rule 6.7 is the standard player-facing prompt.
- **Standards sync** (`standards-sync.md`) — this runbook is acknowledgment-tracked, not sync-vendored. Cog `CLAUDE.md` carries the "Last acknowledged" code; agents check at session start.

## What's exempt

- `chronoforge/` itself — coordinator workspace, not shipped, no players. Comment / error / SV rules don't apply to runbooks. License rule still applies if any code is vendored here.
- `scribe` — different repo shape; out of scope for this proposal.

## Last exercised

_New runbook; not yet exercised._
