# Syndicator Integration Guide

> **Status:** Draft. This document captures the implementation patterns for the Syndicator hard-dep migration (Phase 6a of the Cogworks integration plan). Read this before starting Phase 6a work; specific function names and cache shapes will firm up during implementation.

## Audience

This guide is for the inventory-aware cogs in the Cogworks suite:

- **FlipQueue** — being migrated from its own `Scanner.lua` to Syndicator (Phase 6a)
- **Ledger** — built on top of Syndicator from day one (Phase 6b, not yet started)

Tempo and Maxcraft do **not** consume Syndicator and should not read this document for guidance — they have no inventory dependencies.

## Core principle

**Syndicator owns inventory data. The cog owns domain logic.**

That means:

- Bag / bank / warbank / guild-bank / mail / auction / currency *snapshots* → Syndicator
- Sales reconciliation, posting log, valuation, history, UI, workflow state → cog

Anything that's a derived calculation or a memoized lookup over Syndicator's raw data lives in a small `ItemLookup.lua`-style helper — **not** a parallel scanner.

## Syndicator API surface

Syndicator exposes its API as plain globals (no LibStub registration). Source of truth in your local install: `Interface\AddOns\Syndicator\API\Main.lua`.

### Aggregate queries (use these for "where do I have X")

```lua
local info = Syndicator.API.GetInventoryInfo(itemLink, sameRealm, sameFaction)
-- Returns pre-aggregated cross-character/guild totals.
-- WARNING: This reads the SUMMARY index, which collapses bonusIDs onto item:<id>.
-- For bonusID-aware queries (R1/R2/R3 crafted gear, etc.), walk raw character
-- data instead.

local infoByID = Syndicator.API.GetInventoryInfoByItemID(itemID, sameRealm, sameFaction)
```

### Per-character / per-guild / warband queries

```lua
local chars = Syndicator.API.GetAllCharacters()  -- list of "Name-Realm" keys
local data  = Syndicator.API.GetByCharacterFullName("Toon-Realm")
-- data.bags, data.bank, data.bankTabs, data.mail, data.equipped, data.void,
-- data.auctions, data.currencies, data.money, data.details

local guilds = Syndicator.API.GetAllGuilds()
local guild  = Syndicator.API.GetByGuildFullName("GuildName-Realm")

local warband = Syndicator.API.GetWarband(1)  -- index defaults to 1

local me = Syndicator.API.GetCurrentCharacter()
```

### Currency queries

```lua
local currInfo = Syndicator.API.GetCurrencyInfo(currencyID, sameRealm, sameFaction)
```

### Lifecycle

```lua
if Syndicator.API.IsReady() then
  -- safe to query
end

if Syndicator.API.IsBagEventPending() then
  -- Syndicator has pending events; data may be in flux this frame
end
```

Cogs can also use `LibStub("Cogworks-1.0"):HasSyndicator()` for the same readiness check.

## Event subscription

Syndicator uses Blizzard's `CallbackRegistryMixin`, **not** LibStub callbacks:

```lua
Syndicator.CallbackRegistry:RegisterCallback("BagCacheUpdate", function(_, character, updates)
  -- updates.bags / .bank / .containerBags tells you what's dirty
end, owner)
```

Available events:

- `Ready` — Syndicator finished initial scan
- `BagCacheUpdate` — char bags / bank / reagent bank
- `WarbandBankCacheUpdate` — warband bank tabs
- `MailCacheUpdate` — mailbox attachments
- `EquippedCacheUpdate` — equipped gear
- `AuctionsCacheUpdate` — owned auctions
- `CurrencyCacheUpdate`, `WarbandCurrencyCacheUpdate`
- `GuildCacheUpdate`, `GuildNameSet`
- `VoidCacheUpdate`
- `CharacterDeleted`, `GuildDeleted`

Each cog should subscribe to the events it cares about and **re-emit them as Cogworks events** so sibling cogs can react without needing their own Syndicator dependency:

```lua
local cw = LibStub("Cogworks-1.0")

Syndicator.CallbackRegistry:RegisterCallback("BagCacheUpdate", function(_, character)
  cw:Fire(cw.Events.InventoryChanged, character)
end, ns)

Syndicator.CallbackRegistry:RegisterCallback("MailCacheUpdate", function(_, character)
  cw:Fire(cw.Events.MailChanged, character)
end, ns)

Syndicator.CallbackRegistry:RegisterCallback("AuctionsCacheUpdate", function(_, character)
  cw:Fire(cw.Events.AuctionsChanged, character)
end, ns)
```

This is the bridge that lets the Ledger cog react to FlipQueue's inventory changes without depending directly on Syndicator's event names.

## The lookup cache pattern

Syndicator's per-slot data shape is:

```lua
{ itemID, itemCount, iconTexture, itemLink, quality, isBound, hasLoot }
```

It does **not** pre-compute bind type granularity (BoP / BoE / BtA / BtW / WuE) or item level for bonus-ID variants. Both are derivable from `itemLink` via standard WoW APIs. The cache memoizes those derivations.

```lua
-- ItemLookup.lua (sketch — exact shape will firm up during implementation)
local ItemLookup = ns.ItemLookup or {}
ns.ItemLookup = ItemLookup

local cache = {}  -- [itemKey] = { bindType, ilvl, name, quality }

function ItemLookup:Get(itemLink)
  local itemID, bonusIDs, modifiers = ns:ParseItemLink(itemLink)
  local itemKey = ns:MakeItemKey(itemID, bonusIDs, modifiers)
  local entry = cache[itemKey]
  if entry then return entry end

  local _, _, quality, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(itemLink)
  local detailedIlvl = GetDetailedItemLevelInfo(itemLink)
  local name = GetItemInfo(itemLink)  -- name is first return of GetItemInfo

  if not name or not detailedIlvl then
    -- Item data not yet loaded; don't cache nil. Caller can retry on
    -- GET_ITEM_INFO_RECEIVED.
    return nil
  end

  entry = {
    bindType = bindType,
    ilvl     = detailedIlvl,
    name     = name,
    quality  = quality,
  }
  cache[itemKey] = entry
  return entry
end

function ItemLookup:Invalidate(itemKey)
  cache[itemKey] = nil
end
```

Notes:

- The cache lives in memory only. It rebuilds on `/reload` from Syndicator data on first access.
- For uncached items, listen for `GET_ITEM_INFO_RECEIVED` and call `:Get` again.
- Battle pets use `battlepet:` keys and have their own info APIs — handle as a separate branch.
- This file is roughly 80 LOC and does **not** scan the player's bags. It only memoizes derivations of `itemLink` data we encounter through Syndicator.

## The slot verifier pattern (action path)

Even with Syndicator owning all the read paths, the auto-pull / auto-deposit action path (`BankQueue.lua`) needs to verify that a slot still contains the expected item right before clicking it. Syndicator's data is from the last cache update — typically milliseconds old, but old enough that a race condition during a frantic posting session can mis-click.

This is also the only place where **warbound-until-equipped detection** lives, because WuE state changes when an item is equipped (an equipped WuE item becomes soulbound to that character).

```lua
-- SlotVerifier.lua (lives inside what's left of Scanner.lua, ~150 LOC total)
local SlotVerifier = {}
ns.SlotVerifier = SlotVerifier

function SlotVerifier:VerifySlot(bagID, slotID, expectedItemKey)
  local info = C_Container.GetContainerItemInfo(bagID, slotID)
  if not info or not info.hyperlink then return false, "empty" end

  local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
  local actualKey = ns:MakeItemKey(itemID, bonusIDs, modifiers)
  if actualKey ~= expectedItemKey then return false, "mismatch" end

  return true
end

local WUE_TOOLTIP_TEXT = ITEM_ACCOUNTBOUND_UNTIL_EQUIP  -- locale-aware Blizzard global
function SlotVerifier:IsWarboundUntilEquipped(bagID, slotID)
  local tooltip = C_TooltipInfo.GetBagItem(bagID, slotID)
  if not tooltip then return false end
  for _, line in ipairs(tooltip.lines or {}) do
    if line.leftText and line.leftText:find(WUE_TOOLTIP_TEXT, 1, true) then
      return true
    end
  end
  return false
end

function SlotVerifier:CanMoveToWarbank(bagID, slotID)
  -- Items can go to warbank if: BoE, BtW, BtA, or WuE.
  -- We trust ItemLookup.bindType for the static cases and tooltip-scan for WuE
  -- to handle the per-slot nuance.
  if self:IsWarboundUntilEquipped(bagID, slotID) then return true end

  local info = C_Container.GetContainerItemInfo(bagID, slotID)
  if not info or not info.hyperlink then return false end

  local lookup = ns.ItemLookup:Get(info.hyperlink)
  if not lookup then return false end

  -- bindType: 0=none/BoE, 1=BoP, 2=BoE, 3=BoU, 7=BtA, 8=BtW
  return lookup.bindType == 0 or lookup.bindType == 2 or lookup.bindType == 7 or lookup.bindType == 8
end
```

The slot verifier is the **only** place tooltip scanning happens in post-Phase-6a FlipQueue. Background scanning is gone.

## The Sync.lua rewire

`Sync.lua` exists for one reason: BNet-linked multi-account inventory sharing. A user with two WoW accounts on the same Battle.net sees a unified view across both. **Syndicator is single-account and cannot replace this.**

The rewire keeps Sync.lua as the network/broadcast layer but flips its source of truth.

**Before (current):**
```
Scanner.lua → FlipQueueDB.characters[name] → Sync.lua broadcasts deltas
            → partner FlipQueue → partner FlipQueueDB.characters
```

**After (Phase 6a):**
```
Syndicator → local Sync.lua snapshots Syndicator-shaped delta → broadcast
           → partner Sync.lua decodes → partner FlipQueueDB.partnerAccounts[uuid]
```

Key changes:

- A new `FlipQueueDB.partnerAccounts[uuid]` table holds remote-account inventory data, since Syndicator can't be told about external accounts. Same shape as Syndicator's Characters table.
- The broadcast format becomes Syndicator-shaped (not FlipQueue-shaped). This is a **protocol bump** — both ends must run the new version.
- Cross-account read paths union local Syndicator data with remote partner data via a new helper:

  ```lua
  function ns:GetUnifiedInventory(itemKey)
    -- walk local Syndicator characters + warband
    -- merge with FlipQueueDB.partnerAccounts[*].Characters / .Warband
    -- return aggregated counts keyed by character/account
  end
  ```

- The protocol bump must be called out in the v0.11.0 changelog. Older FlipQueue installs on the partner side cannot decode the new format.

## Caveats and gotchas

- **Summary index collapses bonus IDs.** `Syndicator.API.GetInventoryInfo(itemLink, ...)` returns aggregated data keyed by `item:<id>`, not by full bonus-aware key. For FlipQueue's R1/R2/R3 crafted gear distinction, walk raw `data.bags` / `data.bankTabs` / `data.mail` and key by `ns:MakeItemKey(ns:ParseItemLink(slot.itemLink))`.
- **Mail expiry is estimated.** Syndicator uses a 30-day estimate from send time, not actual expiry timestamps. FlipQueue's `TrackerMail.lua` does not need precise expiry for sales reconciliation; it matches against the post log by sender + subject + amount. So this is not a problem in practice.
- **Mail 50-message visibility cap.** WoW's mail API only exposes up to 50 inbox messages at a time. Syndicator scans what's visible when the mail UI updates; it does NOT implement Postal-style multi-batch refresh to walk past the cap. For FlipQueue's sales-reconciliation use case this is fine — auction-success mail is typically the most recent (front of inbox) so the 50-cap rarely matters. **If a cog needs deeper mail history, layer a refresh helper on top of Syndicator's data — do NOT replace Syndicator with a custom scanner.** The mail-scanning Postal patterns (front-insertion race, `TakeInboxItem` throttling) become irrelevant under Syndicator.
- **Single-account scope.** Syndicator only knows about the current Battle.net account. The Sync.lua rewire above is the *only* way to get cross-account data. Don't expect Syndicator to expose anything from the other linked account.
- **Per-slot updates fire one event per dirty bag.** The `BagCacheUpdate` event includes a dirty descriptor — use it to scope your re-emission and avoid full-cog refreshes on every BAG_UPDATE.
- **Item data load delays.** Newly-encountered items may have nil `itemLink` until WoW finishes loading them. If your cog calls `GetItemInfo(itemLink)` in `ItemLookup`, you'll occasionally hit nil. Use the standard wait-gate (`C_Item.RequestLoadItemDataByID` + `GET_ITEM_INFO_RECEIVED`) and don't cache nil entries.
- **Auctions live update.** Syndicator's `auctions` field tracks current owned auctions live. FlipQueue's historical posting log (status transitions: posted → sold/expired) is still FlipQueue's job and reads mail events for reconciliation.
- **Realm normalization.** Syndicator stores characters keyed by `"Name-RealmNormalized"`. Cogworks's `cw:GetCharacterKey()` uses the same convention so the keyspaces match. Don't roll your own normalization.

## What the cog still owns (everything that isn't inventory)

Don't even think about porting these to Syndicator:

- Sales reconciliation (`TrackerMail.lua` matching mail to post log)
- Auction posting log (`TrackerAuctions.lua` historical state with status transitions)
- Sales index / pricing analytics (`SalesIndex.lua`, `ItemResearch.lua`, `DealFinder.lua`)
- TodoList / to-do generator state (`TodoList.lua`, `TodoGenerator.lua`)
- Import parsers (FlippingPal CSV, AAA JSON, Auctionator imports)
- TSM integration (`TSM.lua`)
- Realm data and accent normalization (`RealmData.lua` — though the canonical version may eventually move into Cogworks-1.0)
- Character role/visibility config
- Bank automation action layer (`BankQueue.lua`)
- The slot verifier described above

For the Ledger cog, the equivalent "owned" list will be:

- Valuation pipeline (TSM source / Auctionator source / FlipQueue rolling-median source / vendor source)
- Snapshot writer + time-series history in `LedgerDB.snapshots`
- Sales subscription via `cw.RegisterCallback(self, cw.Events.SaleLogged, ...)` (FlipQueue fires this from `TrackerMail.lua` when a sale is reconciled)
- Net worth UI

## Implementation order (Phase 6a)

**Prerequisite — `v0.10.2-alpha1` (Phase 1):** Cogworks-1.0 must already be embedded in FlipQueue before Phase 6a starts. This is a separate, user-invisible alpha that adds the `.pkgmeta` external, declares the library in the `.toc`, registers the addon, and ships. No behavior changes. See PLAN.md Phase 1 for the embedding shakedown details. Phase 6a (everything below) ships as **`v0.11.0-alpha1`** in a follow-up release.

1. Add `## Dependencies: Syndicator` to `flipqueue.toc`. Confirm load order is correct.
2. Build `ItemLookup.lua` in isolation. Unit-test against a known itemLink. ~80 LOC.
3. Wire FlipQueue's read paths through `ItemLookup` + Syndicator API behind a `FlipQueueDB.devSyndicatorMode` flag. Both paths run in parallel during dev — don't delete Scanner yet.
4. Validate UI parity: every page that shows inventory should look identical with the flag on vs off. Use `/fq inv` and `/fq gen` as the smoke tests.
5. Build the slot verifier with WuE tooltip detection. Confirm auto-pull/auto-deposit still works.
6. Rewire Sync.lua. This is the trickiest step — test on both single-account and BNet-linked-account setups.
7. Schema migration: add `partnerAccounts` table, clear old `characters[*].inventory` blobs.
8. Delete the old Scanner.lua scanning code and the dev flag. Keep what became the slot verifier.
9. Ship as v0.11.0-alpha1 → beta → stable. Changelog explicitly calls out the new dep and the protocol bump.

## When to come back to this document

This is Phase 6a-specific. Don't try to apply these patterns to Tempo or Maxcraft — those cogs have no inventory dependencies. If you're not actively working on FlipQueue's Syndicator migration or building the Ledger cog, this document is not the one you want. Read `PLAN.md` and `AGENT_BRIEF.md` instead.
