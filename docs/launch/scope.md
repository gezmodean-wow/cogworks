# What's in Cogworks vs. the individual cogs

Cogworks is a **library**, not a feature addon. It exists so the cogs in the suite can talk to each other and share a coherent look without each one reinventing the same primitives. Most users will never install it directly — they'll get it embedded inside FlipQueue, Tempo, Maxcraft, or the upcoming ledger cog.

This page draws a hard line between what belongs in Cogworks and what stays in the individual cogs, so nobody installs the standalone version expecting features it intentionally doesn't have.

---

## In Cogworks-1.0 (the library)

Cogworks ships **primitives**. Anything in this list is something every cog can rely on being present.

| Area | What it provides | Why it's here |
|---|---|---|
| **Event bus** | `CallbackHandler`-backed registry with a canonical event list (`SaleLogged`, `CraftCompleted`, `ResetDue`, `InventoryChanged`, `GoldChanged`, …) | So FlipQueue can react to a Tempo reset, or the ledger can react to a FlipQueue sale, without any hard dependency between the two |
| **Addon registry** | `:RegisterAddon`, `:GetRegisteredAddons` | So an "About" panel in any cog can list its siblings and link to them |
| **Theme palette** | Dark base + gold + arcane-purple + brass trim, plus status and WoW quality colors | So every cog uses the same look without copy-pasting hex values |
| **Character key helper** | `:GetCharacterKey()` returning `"Name-RealmNormalized"` | So all suite data shares one keyspace and matches Syndicator's convention |
| **Syndicator bridge** | `:HasSyndicator()` capability detector | So cogs can *opportunistically* enrich data when Syndicator is loaded, without making it a hard dependency |
| **Print helpers** | `:Print` / `:PrintError` with branded per-cog prefixes | So chat output across the suite has a consistent visual identity |

That's the whole library. Roughly 230 lines of Lua. It is intentionally small.

---

## In Cogworks the standalone addon (extra bits beyond the library)

The standalone install is the library plus a thin development shell:

- A `/cogworks` slash command (`status`, `events`, `fire <ev>`, `help`) for verifying the library loaded
- A one-line "Ready" banner at login

That's it. The standalone exists so developers and curious users can install Cogworks alone, see it work, and read the source. It does not provide any gameplay features.

The slash command and banner **do not** ship in the embedded copies — every cog gets the bare library, no `/cogworks` command leaking into their installs.

---

## NOT in Cogworks (and never will be)

These all live inside the individual cogs that own them. Cogworks does not duplicate, wrap, or replace any of them.

| Lives in | Not in Cogworks |
|---|---|
| **FlipQueue** | The FlippingPal workflow, the buy/sell queue UI, item scanning, sale logging, the `/fq` and `/flipqueue` slash commands, `FlipQueueDB` |
| **Tempo** | Daily/weekly/event reset tracking, the task list UI, the `/tempo` and `/tmp` slash commands, `TempoDB` and `TempoCharDB` |
| **Maxcraft** | Profession optimization, recipe planning, reagent math, the `/maxcraft` and `/mxc` slash commands |
| **Ledger (planned)** | Net worth tracking, sale evaluation, the historical price graph |
| **Syndicator** | The actual inventory scanner. Cogworks only detects whether Syndicator is loaded — it does not scan bags, banks, mail, or the auction house itself |

If you find yourself wishing Cogworks did one of these things, you want the cog that owns it.

---

## Why the split looks like this

Three constraints shape it:

1. **Live users.** FlipQueue and Tempo already ship on CurseForge and Wago with established SavedVariables (`FlipQueueDB`, `TempoDB`, `TempoCharDB`). Cogworks must never claim or rename those — and it doesn't touch SavedVariables at all.
2. **Additive only.** Every Cogworks release bumps `MINOR` and only adds APIs. A breaking change would force every cog to re-release in lockstep, which defeats the entire reason this library exists. The smaller and more boring the surface, the easier this rule is to keep.
3. **Optional, not enforced.** Cogs degrade gracefully if Cogworks is absent. Cross-cog coordination is a bonus, not a requirement. So Cogworks can never own anything load-bearing for a single cog's core flow.
