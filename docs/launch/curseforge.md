# Cogworks — CurseForge listing copy

> Paste this into the CurseForge project description after creating the `cogworks` project under the `gezmodean-wow` author. CurseForge supports a subset of BBCode/HTML — this file is plain markdown so you can convert with their editor.

---

## Short description (one-liner, used in search results)

> The shared mainspring of the Cogworks WoW addon suite — event bus, theme, and cross-cog plumbing for FlipQueue, Tempo, Maxcraft, and beyond.

---

## Long description

**Cogworks** is the shared core library that powers the Cogworks suite of addons by Gezmodean: **FlipQueue**, **Tempo**, **Maxcraft**, and the upcoming ledger cog. It's the mainspring — the thing that lets every cog tick to the same rhythm.

### Do I need to install this?

**Probably not.** Cogworks is bundled inside every cog that uses it (via LibStub embedding), so installing FlipQueue or Tempo already gives you Cogworks. LibStub picks the newest copy automatically — no version conflicts, no duplicate work.

You only need this standalone install if you are:

- A developer building a cog against Cogworks-1.0
- Curious and want to read the source or poke at it with `/cogworks`
- Running a cog that, for any reason, didn't embed its own copy

The standalone install adds a single slash command (`/cogworks`) and a one-line login banner. It does not provide any gameplay features on its own.

### What's inside

- **Event bus** — `CallbackHandler`-backed registry with a canonical event list (`SaleLogged`, `CraftCompleted`, `ResetDue`, `InventoryChanged`, `GoldChanged`, …) so cogs can signal each other without hard dependencies
- **Theme palette** — the dark + gold + arcane-purple look used across every cog
- **Character key helpers** — canonical `"Name-RealmNormalized"` keys that match Syndicator's convention so suite data and Syndicator data share one keyspace
- **Addon registry** — each cog registers itself; any cog can enumerate its installed siblings
- **Syndicator capability bridge** — for cogs that want to opportunistically enrich data when Syndicator is present
- **Print helpers** — branded per-cog chat prefixes

### The Cogworks suite

| Cog       | Role                         | Status                         |
|-----------|------------------------------|--------------------------------|
| FlipQueue | FlippingPal workflow         | Live (CurseForge + Wago)       |
| Tempo     | Reset / task tracker         | Live (CurseForge + Wago)       |
| Maxcraft  | Profession optimization      | In development                 |
| Ledger    | Net worth + sales evaluation | Planned (name TBD)             |

Community hub: the **Chronoforge** Discord server.

### Design promises

- **Additive only.** Every release bumps `MINOR` and only *adds* APIs. Old functions never disappear.
- **No Ace3.** Built on LibStub + CallbackHandler-1.0, matching the rest of the suite.
- **Opt-in.** Cogs degrade gracefully if Cogworks is absent. Cross-cog coordination is a bonus, not a requirement.
- **MIT licensed.** Read it, fork it, build your own cogs against it.

### `/cogworks` commands (standalone install only)

```
/cogworks              show status
/cogworks events       list known event names
/cogworks fire <ev>    fire an event for testing
/cogworks help         show this list
```

### For developers

Embed Cogworks into your cog by adding it to your `.pkgmeta`:

```yaml
externals:
  Libs/Cogworks-1.0:
    url: https://github.com/gezmodean-wow/cogworks
    tag: latest
```

Then add the file to your `.toc` after LibStub and CallbackHandler-1.0:

```
Libs\Cogworks-1.0\Cogworks-1.0.lua
```

Source, issues, and full API docs: **https://github.com/gezmodean-wow/cogworks**

---

## CurseForge project metadata

- **Project name:** Cogworks
- **Project slug:** `cogworks`
- **Category:** Libraries
- **Tags:** library, api, framework
- **Game version:** The War Within (11.0.x)
- **Source URL:** https://github.com/gezmodean-wow/cogworks
- **Issues URL:** https://github.com/gezmodean-wow/cogworks/issues
- **License:** MIT

## Screenshots / images needed

- 400×400 logo (square, used as project avatar)
- 400×200 thumbnail (used in search results)
- 1–2 screenshots of `/cogworks status` output in the chat frame, ideally with one or two cogs registered so the "Registered cogs" line isn't empty
