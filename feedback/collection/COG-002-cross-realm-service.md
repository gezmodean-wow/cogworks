---
id: COG-002
cog: cogworks
status: investigating
title: Cross-realm / character-key service extraction and hardening
sources:
  - type: internal
    session: 2026-04-21
    note: Raised during UI primitive roadmap — cross-realm logic useful to Tally and Tempo beyond FlipQueue's current scope
reporters: []
created: 2026-04-21
updated: 2026-04-21
release: null
tags: [cross-realm, character-keys, service, hardening, tsm]
---

## Summary

Hoist FlipQueue's cross-realm and realm-normalization logic into Cogworks as a shared service. Harden for edge cases encountered in live use. Cogworks becomes the canonical source of `"Name-Realm"` keys, connected-realm graphs, and TSM realm key parsing for the entire suite.

## Reproduction

Current state:

- FlipQueue has `RealmData.lua`, `TSMRealms.lua`, and parts of `Sync.lua` handling realm naming, connected-realm mapping, and TSM `r@realm@...` key parsing.
- Cogworks already provides `lib:GetCharacterKey()` matching Syndicator's `"Name-Realm"` convention — so the foundation exists, but the realm graph + TSM parsing live elsewhere.
- **Tempo** needs realm-local reset cutoffs (EU realms on server time, not client time — long-standing source of daily reset bugs).
- **Tally**, when it ships, will aggregate cross-realm sales/inventory and will need the same logic.

Without extraction, each cog reinvents or copies this logic and diverges over time.

## Attempts

- **2026-04-21**: Roadmap captured. No extraction work yet.

## Notes

### Proposed API (rough shape — refine during extraction)

- `lib:NormalizeRealmName(raw)` — canonical slug form; handles spaces, apostrophes, Unicode.
- `lib:GetConnectedRealms(realmSlug)` → list of slugs (includes the input).
- `lib:ParseTSMRealmKey(tsmKey)` → realm slug (strips `r@realm@...` prefixes). Keep this specifically for TSM-integration use cases; may stay in FlipQueue if no other cog needs it.
- `lib:IsCrossRealmSale(srcRealm, dstRealm)` → bool, using connected-realm graph.
- `lib:GetServerTimezoneOffset(realmSlug)` → for Tempo's realm-local reset timing. Harder — may need a lookup table or a probing approach. Investigate during extraction.
- Expand `lib:GetCharacterKey(name, realm)` edge-case handling (foreign characters, server transfers, trailing whitespace).

### Hardening test matrix

- Non-ASCII realm names (EU-RU, EU-DE, Korean client, Chinese client).
- Connected-realm graph updates (Blizzard merges realms periodically — cache invalidation strategy needed).
- Realm transfers mid-tracking (character moves; old realm data lingers).
- Connected-realm auction cross-listing vs isolated realms.
- TSM realm key variants across TSM major versions.
- Cases where `GetRealmName()` returns differently than the connected-realm list expects.
- Whitespace-normalized charKeys (FlipQueue already handles this in TrackerTSMReconcile; promote the normalization helper).

### Consumers

- **FlipQueue** — current owner; migration to the Cogworks service without regression is the gating concern. Must shadow-parallel before cutover.
- **Tempo** — realm-local reset cutoffs. EU server time reset timing has been a long-standing pain point.
- **Tally** — cross-realm sales/inventory aggregation (when tally ships).
- **Ledger** (future, planned) — inventory-aware cog, same Syndicator keyspace.

### Relationship to Syndicator

Syndicator uses `"Name-Realm"` keys with a specific normalization. Whatever we build must match Syndicator's behavior exactly on the `GetCharacterKey` side — or explicitly document the divergence. Cogworks is already aligned per the existing design principles; don't drift during extraction.

### What stays in FlipQueue

- TSM sales CSV parsing (`TrackerTSMReconcile.lua` as a whole — it's FlipQueue-specific business logic).
- Auction-house tracking state machines (`TrackerAuctions.lua`, `TrackerMail.lua`).
- Only the *helpers* these use (realm normalization, connected-realm lookup, optionally `ParseTSMRealmKey`) move to Cogworks.

## Next steps

1. **Investigation**: read FlipQueue's `RealmData.lua`, `TSMRealms.lua`, `Sync.lua` end-to-end; inventory every realm-touching function and edge case handled. Produce an extraction-scope doc.
2. **Design the service API** — what moves to Cogworks, what stays in FlipQueue. Decide whether TSM-specific parsing moves (if Tally also uses TSM) or stays FlipQueue-local.
3. **Build shadow-parallel** — add the Cogworks service; have FlipQueue call it alongside its existing code; compare outputs live until confidence is high. Log divergences during verification.
4. **Cut over** — FlipQueue uses the Cogworks service directly; delete local duplicates. Alpha → beta → stable promotion over multiple weeks given live-user exposure.
5. **Consumer adoption** — once stable, surface to Tempo and Tally as they need it. Each consumer addition is a separate migration step.
