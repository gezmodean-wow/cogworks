# Agent Brief: Cogworks WoW Addon Suite

> **You are an agent looking at the shared core of a multi-cog WoW addon suite.** This document is the single entry point. Read it, then read the other documents in the order suggested. Total ramp-up should be under 10 minutes.

## What this is

**Cogworks** is a productivity suite of World of Warcraft addons authored by Gezmodean. The shared core is an embeddable LibStub library at `C:\src\cogworks\` (`Cogworks-1.0`) that each member addon ("cog") bundles via `.pkgmeta` externals.

The branding draws on **chronomancy** (WoW's school of time magic) and **arcane clockwork machinery**. Devs are called "Chronosmiths." The community Discord is "Chronoforge." This lore is used lightly — public API names and user-facing labels stay plain; flavor lives in TOC notes, README prose, and About panels.

## The cogs

| Cog       | Repo path             | What it does                            | Status                          |
|-----------|-----------------------|-----------------------------------------|---------------------------------|
| FlipQueue | `C:\src\flipqueue`    | FlippingPal AH workflow assistant       | LIVE on CurseForge + Wago       |
| Tempo     | `C:\src\Tempo`        | Cross-character reset/task tracker      | LIVE on CurseForge + Wago       |
| Maxcraft  | `C:\src\maxcraft`     | Profession optimization coach           | In development (pre-release)    |
| _Ledger_  | _(not yet created)_   | Net worth + sales evaluation            | Planned (name TBD)              |

All four are (or will be) under the `gezmodean-wow` GitHub organization. Each cog has its own `CLAUDE.md` with cog-specific conventions and a brief Cogworks suite context section.

## Reading order

If you have ~10 minutes, read in this order:

1. **`C:\src\cogworks\README.md`** — public-facing pitch and how to embed Cogworks-1.0 in a cog (~3 min)
2. **`C:\src\cogworks\CLAUDE.md`** — design principles, dependency strategy, live-user constraints, release flow (~3 min)
3. **`C:\src\cogworks\docs\PLAN.md`** — full integration plan: architecture decision, Syndicator strategy, phased rollout (Phases 0-7), ledger sketch, branding voice, risk table (~4 min)

If you're going to touch inventory code (FlipQueue or the planned Ledger):

4. **`C:\src\cogworks\docs\SYNDICATOR_INTEGRATION.md`** — implementation patterns for the Syndicator hard-dep migration. Phase 6a-specific. (~5 min)

If you're going to touch the library itself:

5. **`C:\src\cogworks\Cogworks-1.0\Cogworks-1.0.lua`** — the library is small (~210 lines) and heavily commented

## The three things you must NOT do without asking

1. **Do not rename or restructure SavedVariables for live cogs.** `FlipQueueDB`, `TempoDB`, `TempoCharDB` are public surface — they have live users on CurseForge and Wago. Renaming breaks every existing install. Maxcraft (`MaxcraftDB`, `MaxcraftCharDB`) is pre-release and rebrandable, but check first.

2. **Do not change slash commands for live cogs.** `/fq`, `/flipqueue`, `/tempo`, `/tmp` are user muscle memory. `/maxcraft`, `/mxc` are pre-release and changeable but should still be confirmed.

3. **Do not break the `Cogworks-1.0` library API.** It is additive-only. Bump `MINOR` for new functions; never remove or rename. A breaking change forces every cog to re-release in lockstep, which defeats the entire reason the library exists.

## Architectural decisions you should know about

- **No Ace3.** Whole suite is built on LibStub + CallbackHandler-1.0 + LibDataBroker-1.1 + LibDBIcon-1.0 + (now) Cogworks-1.0. This is intentional and consistent across cogs. Don't suggest adopting Ace3.
- **Syndicator is a hard dependency for inventory-aware cogs.** FlipQueue and the planned Ledger declare `## Dependencies: Syndicator` and consume its API directly with no fallback scanner. Tempo and Maxcraft do not depend on Syndicator. Cogworks-1.0 itself stays dep-free. See `docs/PLAN.md` "Syndicator strategy" section for the rationale.
- **Cogworks-1.0 ships embedded, not as a separate user install.** Each cog bundles it via `.pkgmeta` externals. LibStub handles version collisions. Existing FlipQueue/Tempo users do not need to install anything new when this rolls out.
- **Phased rollout protects live users.** See PLAN.md phases 0-7. Never refactor all three live cogs in parallel — one at a time, alpha → beta → stable, week between releases.
- **The user prefers consolidation over conservative dual-path designs.** When proposing architecture, lead with the simpler unified design; only add fallbacks when there's a concrete population of users they serve.

## Where to find conversation context (Claude Code agents only)

If you are a Claude Code agent invoked from `C:\src\cogworks`, project memory is at `C:\Users\gezmo\.claude\projects\C--src-cogworks\memory\` and auto-loads. Key files:

- `cogworks_suite.md` — suite composition, live-user constraints, Syndicator dependency strategy, Phase 6a preservation list
- `chronomancy_branding.md` — branding voice guidelines (light touch lore)
- `feedback_consolidation_over_caution.md` — engineering preference: prefer consolidation over parallel-path fallbacks
- `user_profile.md` — user is Gezmodean, ships under gezmodean-wow GitHub org, no-Ace3 stack

If you are invoked from a cog repo (`C:\src\flipqueue` etc.), this brief and the cogworks docs are your primary context — the cogworks memory does not auto-load there. Each cog repo has a brief Cogworks suite context section in its own `CLAUDE.md` pointing back here.

## Quick decision tree

- **Adding a new feature to a single cog?** Read that cog's `CLAUDE.md` first. If the feature is generic enough that another cog might want it later, consider whether it belongs in `Cogworks-1.0` instead.
- **Refactoring something that exists in multiple cogs?** It's a candidate for extraction into Cogworks-1.0. See PLAN.md phases 2-4 for what's already planned.
- **Touching inventory data?** Read `SYNDICATOR_INTEGRATION.md` first. Inventory-aware cogs (FlipQueue, Ledger) read from Syndicator, not from their own scanners.
- **Touching SavedVariables?** Stop. Confirm with the user before any schema change to a live cog. Always add a migration canary in `Migration.lua` before changing schema.
- **Changing the library API?** Bump MINOR in `Cogworks-1.0.lua`. Never remove or rename existing functions. Add new ones alongside.
- **Adding a new cog?** It joins the suite by embedding `Cogworks-1.0` via `.pkgmeta` externals. See README.md for the embedding pattern. Pick a name that fits the chronomancy/clockwork voice loosely but stays clear.

## When in doubt

- Live-user impact > implementation elegance
- Consolidation > duplication
- Plain words in API names > chronomancy lore
- Ask before risky operations; the user has named live SavedVariables, slash commands, and the addon names themselves as immutable
