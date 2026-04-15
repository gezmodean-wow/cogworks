# Cogworks Suite Integration Plan

This document captures the architectural plan for turning FlipQueue, Tempo, and Maxcraft into a unified suite ("Cogworks") while protecting existing live users.

## Current state

| Cog       | Role                         | Published | SavedVariables                 | Slash commands       |
|-----------|------------------------------|-----------|--------------------------------|----------------------|
| FlipQueue | FlippingPal workflow         | YES       | `FlipQueueDB`                  | `/fq`, `/flipqueue`  |
| Tempo     | Reset / task tracker         | YES       | `TempoDB`, `TempoCharDB`       | `/tempo`, `/tmp`     |
| Maxcraft  | Profession optimization      | NO (dev)  | `MaxcraftDB`, `MaxcraftCharDB` | `/maxcraft`, `/mxc`  |
| _Ledger_  | Net worth + sales evaluation | Planned   | TBD                            | TBD                  |

All three existing cogs share the same no-Ace stack (LibStub + CallbackHandler-1.0 + LibDataBroker-1.1 + LibDBIcon-1.0), the same `local addonName, ns = ...` namespace pattern, and a near-identical dark TSM-style theme. Tempo's own docs already describe its approach as "adopting FlipQueue DNA" — the patterns are consciously shared, they've just never been factored out.

## Core architectural decision

**Ship Cogworks as an embeddable LibStub library (`Cogworks-1.0`), bundled into each cog at package time via `.pkgmeta` externals.**

Not as a hard dependency addon. Not as an umbrella that ships everything together.

Why:
- **Zero user-facing change.** No new install required for existing FlipQueue/Tempo users.
- **Proven pattern.** This is how every WoW library ships (Ace3, LibStub, LibDataBroker).
- **Independent release cadence.** Each cog ships when its author wants; Cogworks-1.0 bumps only on additive API changes.
- **Graceful degradation.** LibStub handles version collisions; the newest embedded copy wins.

## Syndicator strategy

[Syndicator](https://github.com/plusmouse/Syndicator) (by the Baganator author) is the de-facto community library for cross-character inventory data. It exposes a `Syndicator.API` surface and a `Syndicator.CallbackRegistry` event bus, and battle-tests its debounced scanning against the entire Baganator userbase. Available on **both CurseForge and Wago.**

**Inventory-aware cogs declare Syndicator as a HARD dependency.** This is a deliberate architectural decision: parallel scanner implementations are exactly the kind of duplication the Cogworks consolidation effort exists to eliminate.

Per-cog stance:
- **FlipQueue** → `## Dependencies: Syndicator` (hard). FlipQueue's existing `Scanner.lua` (~750 LOC) collapses to a thin "verify slot before click" layer (~150 LOC) used only on the action path (auto-pull, auto-deposit). All cross-character inventory queries route through `Syndicator.API`.
- **Ledger** (planned) → `## Dependencies: Syndicator` (hard from day one). Built as a pure consumer with no scanning code at all.
- **Tempo** → no Syndicator dep. Reset tracking doesn't need bag data.
- **Maxcraft** → no Syndicator dep. Profession coaching only needs current-character data; `C_Container` is sufficient.
- **Cogworks-1.0** → no dep. It's a library; dep declaration belongs to consumers.

Why hard deps over optional + fallback:
1. **It deletes ~600 LOC of Scanner.lua, not duplicates it.** Syndicator solves the same problem better (bank tabs, warband tabs, mail expiry, currencies, void storage, auctions, debounced scanning).
2. **The fallback path is dead code in practice.** FlipQueue's audience already runs Baganator → already has Syndicator. Maintaining a parallel scanner taxes every new feature.
3. **Reliability is reversed.** Syndicator is more stable than FlipQueue's Scanner because it has Baganator's userbase hitting edge cases.
4. **Alpha lets us be brave.** FlipQueue v0.10.x users tolerate "v0.11.0 now requires Syndicator" via changelog. CurseForge auto-installs hard deps; Wago carries Syndicator too.

The one place a Syndicator-free fallback is preserved: the action path (BankQueue's auto-pull/deposit slot clicking) needs live slot enumeration regardless of what's in Syndicator's cache, because Syndicator's data is from the last scan and could be stale by milliseconds. That's a small "verify before click" helper, not a parallel scanner.

**Patterns to emulate from Syndicator inside Cogworks** (not reimplement, just learn from):
1. **Single CallbackRegistry with an explicit event-name list.** Cogworks already does this (`lib.Events` in `Cogworks-1.0.lua`).
2. **Dirty-pending + OnUpdate coalesce** for any cog that reacts to bursts of events of its own. One `SetScript("OnUpdate", fn)` that clears itself on first tick coalesces a burst into a single response.
3. **`"Name-RealmNormalized"` character keys.** Cogworks uses this convention by default so its data and Syndicator's data share a keyspace.

Patterns we previously considered importing into Cogworks (debounced bag-scan coalesce, `LoadItemData` wait-gate) are now Syndicator's job, not ours. We just consume the events it fires.

## What lives in Cogworks-1.0

**Phase 0 (shipped):**
- Event bus with canonical `Events` table
- Addon registry (cogs register themselves, siblings can enumerate)
- Theme constants (dark + gold + arcane purple)
- Character-key helper matching Syndicator convention
- Print helpers with per-cog branded prefixes
- Syndicator capability check
- `Ready` event fired at `PLAYER_LOGIN`

**Phase 1-2 additions (planned):**
- DB / migration framework (`ApplyDefaults` deep-merge + schema version runner)
- Realm utilities (accent normalization, connected realms — source of truth: FlipQueue `RealmData.lua`)
- Character registry (class / level / faction / last-seen)
- Time / reset math (source of truth: Tempo `Core/Time.lua`)
- Item utilities (`MakeItemKey`, `ItemsMatch`, `ParseItemLink`, `ParseGoldValue` — source: FlipQueue `Core.lua`)
- ID generator (hex from time+random — source: Tempo `Core.lua`)

**Phase 3 additions (planned):**
- ScrollTable widget (source: FlipQueue)
- MinimapButton helper (LDB + LibDBIcon wrapper)
- Themed frame factory

**What STAYS per-cog (never extracted):**
- FlipQueue: TSM/Auctionator integration, Transformer pipeline, BankQueue (action layer), Tracker modules, TodoGenerator, DealFinder, Sync
- Tempo: TaskManager/TaskList/Scheduler, reset detectors + provider rules, template engine
- Maxcraft: Step engine + StepLibrary evaluators, profession/buff/reagent data, CraftCoach/GatherCoach widgets
- Ledger: valuation model, time-series history, net-worth UI

## Phased rollout (live-user safe)

### Phase 0 — Bootstrap *(done)*

Cogworks repo scaffolded at `C:\src\cogworks\`. `Cogworks-1.0.lua` library with event bus, addon registry, theme, character keys, Syndicator bridge, print helpers. Standalone `cogworks.toc` and BigWigsMods packager pipeline. No cog depends on it yet. Risk: zero.

### Phase 1 — Prove the embedding pipeline

Each cog adds Cogworks-1.0 as a `.pkgmeta` external, declares it in its `.toc`, registers itself with the library, and ships a no-behavior-change alpha that proves the embedding works.

1. Add `Libs/Cogworks-1.0` external to the cog's `.pkgmeta`.
2. Add `Libs\Cogworks-1.0\Cogworks-1.0.lua` to the cog's `.toc` (after LibStub and CallbackHandler-1.0).
3. In the cog's Core, `LibStub("Cogworks-1.0"):RegisterAddon("CogName", { version = "..." })` and a debug slash that prints via `cw:Print("CogName", "hello")`.
4. Build locally, confirm the library loads, event bus works.
5. Ship an alpha. **No behavior changes** — this alpha is bisectable in isolation if any embedding issue surfaces later.

**Per-cog cadence:**
- **Maxcraft** is the preferred first test bed because it's unpublished, but it is **not a gate**. Phase 1 is mechanically trivial; any embedding pipeline issues would surface on any cog.
- **FlipQueue Phase 1 lands as `v0.10.2-alpha1`** specifically — embed Cogworks, no behavior changes, ship. This makes Phase 6a (which is `v0.11.0-alpha1`) two clean bisectable diff sets instead of one big risky combined alpha.
- **Tempo Phase 1** lands as a normal alpha bump.
- Cogs with their own validation paths can land Phase 1 in parallel — the "never refactor all three in parallel" rule applies to risky refactors (Phase 6a-style), not user-invisible embedding alphas.

**Ship criterion:** all three cogs boot normally with Cogworks-1.0 embedded, no regressions visible to users.

### Phase 2 — Land the lowest-risk shared utilities

In this order (easiest to rollback first):
1. **Print helpers + debug ring buffer** — each cog's local helpers become thin delegators. Keep old functions for one release as a safety net.
2. **Theme constants** — each cog's `UI/Shared.lua` palette pulls from `cw.Theme`. Pixel-identical result.
3. **Event bus adoption** — Tempo and Maxcraft route their custom events through `cw.callbacks`; FlipQueue's native-event approach stays as-is or adopts opportunistically.

Each change lands as alpha → beta → stable per cog, one cog at a time. **Never refactor all three in parallel.**

### Phase 3 — Migrate DB helpers, realm data, character registry

Highest-risk phase because it touches SavedVariables. Rules:
- **SV global names do not change.** Cogworks provides helpers; each cog still owns `FlipQueueDB` / `TempoDB` / etc.
- Bump each cog's schema version by 1 and add a **no-op migration canary** — proves the new path is hit and gives a rollback marker.
- Test each migration on a copy of real `SavedVariables\*.lua` from a live character before shipping.
- Ship one cog at a time, wait a week between, monitor Discord / Wago / CurseForge for corruption reports.

### Phase 4 — Migrate UI widgets

ScrollTable, MinimapButton, themed frame factory move into Cogworks. Cogs delete their local copies. Pure presentation change → low risk. Do a visual walkthrough of every page of every cog before shipping.

### Phase 5 — Branding pass *(first user-visible change)*

Only after Phases 0-4 are stable for ~2 weeks with no regressions.

Per cog:
- Update TOC `## Notes` to mention "Part of the **Cogworks** suite — join us at Chronoforge."
- Add an "About / Cogworks" section in existing settings page with:
  - One-paragraph suite pitch
  - Chronoforge Discord link (click-to-copy field)
  - Sibling cog list with "installed ✓ / not installed" detection via `C_AddOns.GetAddOnInfo` (and via `cw:GetRegisteredAddons()` for runtime confirmation)
  - "Powered by the Mainspring (Cogworks-1.0 v...)" footer
- CurseForge / Wago project descriptions get the Cogworks pitch added on top.
- No slash command changes. No SV changes.

### Phase 6 — Make Syndicator the inventory data layer

Two coordinated sub-releases that share the architectural assumption "Syndicator owns inventory data."

**6a — FlipQueue Scanner collapse** *(refactor an existing live cog)*

The 2026-04-10 audit of FlipQueue's data model against Syndicator's API confirmed Phase 6a is feasible but identified specific subsystems that must be preserved or rewired. See `docs/SYNDICATOR_INTEGRATION.md` for the implementation patterns.

**What gets deleted (~600 LOC out of `Scanner.lua`):**
- Bag scanning, bank-tab scanning, warband-bank scanning, guild-bank scanning loops
- Cross-character inventory persistence in `FlipQueueDB.characters[*].inventory`
- Per-character `lastScan` / `lastBankScan` bookkeeping
- Bind-type and ilvl pre-computation on every scan (replaced by lazy lookup cache)

**What stays in `Scanner.lua` (~150 LOC of action-path safety):**
- "Verify slot before click" helper used by `BankQueue` auto-pull/auto-deposit
- Tooltip scan for warbound-until-equipped state — this is per-slot and changes when an item is equipped, so it must be live, not cached
- Item-load wait gate so click handlers don't fire on uncached items

**What gets rewired but kept (`Sync.lua`):**
- BNet-linked multi-account sync has no Syndicator equivalent (Syndicator is per-account). It must stay.
- Source-of-truth on the local side flips from `Scanner.lua` output to `Syndicator.API` queries
- Broadcast format becomes Syndicator-shaped (slight protocol bump)
- Receiving side stores partner-account data in a new `FlipQueueDB.partnerAccounts[uuid]` table since Syndicator can't be told about external accounts
- Cross-account read paths union local Syndicator data with remote partner data via a new `ns:GetUnifiedInventory(itemKey)` helper

**What gets added (~80 LOC new):**
- A lazy `{[itemKey] = {bindType, ilvl, name, quality}}` lookup cache, populated as we walk Syndicator data via `C_Item.GetItemInfo(itemLink)` and `GetDetailedItemLevelInfo(itemLink)`. This is NOT a scanner — it's memoized derivation. Lives in a new small file like `ItemLookup.lua`.
- A thin Cogworks event re-emitter: subscribe to Syndicator's `BagCacheUpdate`, `WarbandBankCacheUpdate`, `MailCacheUpdate`, `AuctionsCacheUpdate` and fire `cw.Events.InventoryChanged` / `MailChanged` / `AuctionsChanged` for any sibling cog (the ledger) that wants them.

**What is NOT touched (these were never inventory data):**
- `TrackerMail.lua` — sales reconciliation (matching incoming auction-success mail against the post log). Stays.
- `TrackerAuctions.lua` — auction posting log with status transitions. Live current-auctions state can come from Syndicator's `auctions` field, but the historical post log is FlipQueue's. Stays.
- `SalesIndex.lua`, `ItemResearch.lua`, `DealFinder.lua` — analytics and pricing. Stay.
- `TodoList.lua`, `TodoGenerator.lua`, import parsers, role/visibility config. Stay.
- `TSM.lua`, `RealmData.lua` — domain integrations. Stay (though `RealmData.lua` may eventually migrate into Cogworks-1.0 in a later phase).

**Net effect:** roughly **-370 LOC** across FlipQueue. Smaller than a naive "delete Scanner.lua entirely" estimate because of the Sync.lua rewire (~100 LOC of changes inside the existing file) and the lookup-cache addition (~80 LOC new). But the simplification is real and every read path becomes more reliable because Syndicator has Baganator's userbase hitting edge cases.

**Migration steps:**

*Prerequisite:* Cogworks-1.0 already embedded in FlipQueue via Phase 1 (shipped as `v0.10.2-alpha1`). Phase 6a starts from a known-good embedding state, not from a cold start.

1. Add `## Dependencies: Syndicator` to `flipqueue.toc`. Minor version bump to **v0.11.0-alpha1**.
2. Schema version bump in `Migration.lua` with a one-shot migration that clears the old `FlipQueueDB.characters[*].inventory` blobs. Keeps the character record (gold, role, guild, lastLogin) and adds an empty `partnerAccounts` table for the Sync.lua rewire.
3. Build `ItemLookup.lua` in isolation. Unit-test against known itemLinks.
4. Land Scanner.lua collapse + ItemLookup.lua addition + Sync.lua rewire on a side branch behind a `FlipQueueDB.devSyndicatorMode` flag. Both paths run in parallel during dev — don't delete Scanner yet. Validate UI parity (`/fq inv`, `/fq gen`) with the flag on vs off.
5. Build the slot verifier with WuE tooltip detection. Confirm auto-pull/auto-deposit still works.
6. Smoke test the Sync.lua rewire on both single-account and BNet-linked-account setups.
7. Delete the dev flag and the old scanning code. Ship as alpha → beta → stable. Changelog explicitly calls out the new Syndicator dependency AND the protocol bump for cross-account sync (older FlipQueue installs on the partner side cannot decode the new format — both sides must update).

**6b — Ledger cog v0.1.0** *(new addon)*
- See "Ledger cog" section below.
- Hard dep on Syndicator from day one. No legacy state to migrate.

### Phase 7 — (Optional) Standalone Cogworks hub addon

A tiny separate addon that, if installed:
- Registers `/cogworks` slash → opens a dashboard with tiles for each installed cog
- One unified minimap button (users can disable per-cog minimap buttons)
- Suite-wide settings (theme tint, debug mode, Chronoforge link)

Opt-in. Cogs remain fully functional without it.

## Ledger cog (new)

**Purpose:** cross-character net worth tracking, sales history analytics, and "is this sale actually profitable?" evaluation.

**Dependencies:** `## Dependencies: Syndicator` (hard) + embeds `Cogworks-1.0`.

**Data model:**
- **Inventory + gold + currencies + auctions + mail:** read directly from Syndicator (`Syndicator.API.GetAllCharacters()`, `GetByCharacterFullName()`, `GetWarband(1)`, `GetCurrencyInfo()`). The ledger has zero scanning code of its own.
- **Prices:** pluggable valuation source — TSM first, Auctionator second, FlipQueue sales-rolling-median third, vendor price fourth. Each source registers with Cogworks via `cw:Fire(cw.Events.PriceUpdated, ...)`.
- **Sales log:** FlipQueue fires `cw.Events.SaleLogged` when a mail confirms a sale; the ledger subscribes via `cw.RegisterCallback` and persists each sale into `LedgerDB` with timestamp, item key, price, cost basis (if known), and net P&L.
- **Time-series history:** ledger writes net-worth snapshots into `LedgerDB.snapshots` on login, on /reload, and on major inventory events (debounced). Syndicator only stores current state; history is the ledger's job.

**Estimated size:** <1500 LOC because the scanning layer is gone entirely.

**Name candidates** (in rough order of preference — pick what feels right):
1. **Chronicle** — chronomancy-adjacent, implies a historical ledger. Downside: generic word, may already be taken on CurseForge.
2. **Reckoner** — "a reckoning of accounts" also means a reckoning of time. Clockwork + finance. Strong.
3. **Countinghouse** — a medieval finance hall; pairs well with "Chronoforge."
4. **Treasury** — plain and clear; no flavor.
5. **Abacus** — counting device, mechanical. Cute but might feel small.
6. **Escapement** — the clockwork part that governs the release of energy (i.e. time-based cashflow). Most on-theme but most cryptic.

Suggested TOC name pattern matching the suite: lowercase folder (e.g. `reckoner`, `chronicle`), PascalCase display title.

## Branding / chronomancy voice (light touch)

**Use in:** TOC notes, README / CurseForge pitches, About panels, internal module names that read cleanly, loading tips, Discord copy.

**Don't use in:** slash command help, feature labels, API method names, error messages, schema migration messages.

**Vocabulary:**
- Suite → **Cogworks**
- Individual addon → **cog**
- Author / contributor → **Chronosmith**
- Community → **Chronoforge** (Discord)
- Shared library → **the Mainspring** (poetic name for Cogworks-1.0)

**Visual:** existing dark TSM base + gold primary. Layer subtle arcane purple (`#8b5cf6`) for "time magic" moments (reset-soon warnings, profit-surge callouts). Gold stays primary accent.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| LibStub version collision between cogs | Standard LibStub behavior handles this. Always bump `MINOR` on additive changes; never break old method signatures. |
| SavedVariables corruption during DB helper migration | Schema version canary + no-op migration first; test on real SV copies; stagger cog releases by a week. |
| "Why is FlipQueue suddenly talking about Cogworks?" confusion | Phase 5 (branding) lands only after technical phases are stable. About panel explains the suite. Discord link provides a Q&A surface. |
| "Cogworks" already taken on CurseForge | Check before publishing the standalone `cogworks` addon. Embedded library path doesn't need a CurseForge slot. |
| Syndicator API changes | Plusmouse maintains a stable API contract (Baganator depends on it). If the upstream API ever shifts, FlipQueue and Ledger pin to a known-working Syndicator version range in their TOC. The `Cogworks-1.0` library has zero Syndicator code so a Syndicator break never cascades to Tempo or Maxcraft. |
| FlipQueue user surprised by new hard dep | Changelog and CurseForge/Wago description explicitly call it out. CurseForge's client auto-installs hard deps. FlipQueue is alpha — early adopters tolerate version bumps. |
| Release coordination burden grows | Each cog releases independently. Cogworks-1.0 externals **pin to tags**, not `main`, so a Cogworks update doesn't auto-ship until each cog repins. |
| Ledger needs features Syndicator doesn't expose | Ledger can scan specific slots directly on its own character while still using Syndicator for cross-character rollups. Hybrid is fine in degenerate cases. |

## First concrete steps (after bootstrap)

1. Create the cogworks repo on GitHub under `gezmodean-wow/cogworks`, push this scaffold.
2. Tag `v0.1.0-alpha1`, verify the packager pipeline runs and produces a valid zip.
3. Wire Maxcraft as the first consumer (Phase 1). Add `Libs/Cogworks-1.0` external, embed, register the addon, prove the event bus works via a debug slash.
4. Only after Maxcraft is proven: wire Tempo, then FlipQueue.
5. Start Phase 2 extractions: print helpers + theme constants first.
