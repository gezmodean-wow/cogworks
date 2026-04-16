# Changelog

All notable changes to Cogworks-1.0 are tracked here. The library is **additive only** — old APIs never disappear, so every entry below is something gained, never lost.

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
