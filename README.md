# Cogworks

**The mainspring of the Cogworks WoW addon suite.**

Cogworks is the shared core that powers FlipQueue, Tempo, Maxcraft, and future cogs. It is built and maintained by Gezmodean and supported by the **Chronoforge** Discord community.

## What it is

Cogworks ships two ways from this one repo:

1. **A standalone WoW addon** (`cogworks`) you can install on its own for local development and debugging.
2. **An embeddable LibStub library** (`Cogworks-1.0`) that each cog bundles inside its own `Libs/` folder via `.pkgmeta` externals. LibStub handles version collisions automatically.

Existing FlipQueue and Tempo users do not need to install anything new — their next update will embed Cogworks transparently.

## What's inside

- **Event bus** — a shared `CallbackHandler`-backed registry with a canonical event list (`SaleLogged`, `CraftCompleted`, `ResetDue`, `InventoryChanged`, `GoldChanged`, ...) so cogs can signal each other without hard dependencies
- **Theme constants** — the dark + gold + arcane-purple palette used across every cog
- **Character-key helpers** — canonical `"Name-RealmNormalized"` keys that match Syndicator's convention so cogworks data and Syndicator data can be cross-referenced without a translation layer
- **Addon registry** — each cog registers itself on load; any cog can enumerate its installed siblings for About panels or cross-promotion
- **Syndicator bridge** — a capability detector so cogs that consume Syndicator share one code path
- **Print helpers** — branded per-cog chat prefixes

## Suite members

| Cog       | Role                         | Status                         |
|-----------|------------------------------|--------------------------------|
| FlipQueue | FlippingPal workflow         | Live (CurseForge + Wago)       |
| Tempo     | Reset / task tracker         | Live (CurseForge + Wago)       |
| Maxcraft  | Profession optimization      | In development                 |
| _Ledger_  | Net worth + sales evaluation | Planned (name TBD)             |

Community hub: the **Chronoforge** Discord server.

## Using Cogworks from a cog

**Add the external to your cog's `.pkgmeta`:**

```yaml
externals:
  Libs/Cogworks-1.0:
    url: https://github.com/gezmodean-wow/cogworks
    tag: latest
```

**Add the library file to your cog's `.toc`** (after LibStub and CallbackHandler-1.0):

```
Libs\Cogworks-1.0\Cogworks-1.0.lua
```

**Use it:**

```lua
local cw = LibStub("Cogworks-1.0")

cw:RegisterAddon("MyCog", { version = "1.2.3" })
cw:Print("MyCog", "hello from a Chronosmith")

-- Listen for a cross-cog event
cw.RegisterCallback(self, cw.Events.SaleLogged, function(_, itemKey, price, qty, source)
  -- react to a sale logged by FlipQueue or the ledger
end)

-- Fire one
cw:Fire(cw.Events.CraftCompleted, recipeID, cw:GetCharacterKey())
```

## Versioning

- `lib.version` — human-facing semver of the Cogworks suite (e.g. `"0.1.0"`)
- `lib.minorVersion` — LibStub minor, bumped on every API addition

Cogworks is **additive only**. Old functions never disappear; only new ones are added. A breaking change would force every cog to re-release in lockstep, which is exactly what this library exists to avoid.

## License

MIT — see [LICENSE](LICENSE).
