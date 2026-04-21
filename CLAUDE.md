# Cogworks — Claude Code guidance

Cogworks is the shared core library of a WoW addon suite authored by Gezmodean (`gezmodean-wow` on GitHub) and supported by the **Chronoforge** Discord community.

## What this repo is

A single LibStub-registered library (`Cogworks-1.0`) distributed two ways:

1. **Standalone addon** — `cogworks.toc` loads the library for local testing. Publishable on CurseForge as a reference install, though most users will get it embedded.
2. **Embeddable library** — each sibling cog (FlipQueue, Tempo, Maxcraft, and the planned ledger cog) pulls Cogworks-1.0 into its own `Libs/` folder via `.pkgmeta` externals at packaging time.

LibStub handles version collisions: the newest `MINOR` loaded wins, and older copies short-circuit at the `NewLibrary` call.

## Design principles

- **No Ace3.** Follows the same no-Ace stack as the rest of the suite: LibStub + CallbackHandler-1.0 + (optionally) LibDataBroker-1.1 + LibDBIcon-1.0. Both LibStub and CallbackHandler are already loaded by LibDataBroker in every existing cog, so Cogworks adds no new library cost.
- **Additive only.** Every release bumps `MINOR`. Never remove an existing API — add new functions, leave the old ones alone. A breaking change would force every cog to re-release in lockstep, which defeats the entire point of the library.
- **Opt-in, not enforced.** Cogs degrade gracefully if Cogworks is absent. Never assume cross-cog coordination is available — it's a bonus, not a requirement.
- **Syndicator is a hard dependency for inventory-aware cogs.** FlipQueue and the planned ledger cog declare `## Dependencies: Syndicator` (not optional) and consume its API directly — no fallback scanner. Tempo and Maxcraft do not depend on Syndicator at all. Cogworks-1.0 itself stays dep-free (it's a library; dep declaration belongs to consumers). Cogworks provides canonical `"Name-Realm"` character keys that match Syndicator's convention so all suite data shares one keyspace, plus a `HasSyndicator()` helper for cogs that want to *opportunistically* enrich data without making Syndicator a hard requirement. See `docs/PLAN.md` for the full strategy.
- **Chronomancy + clockwork, light touch.** Lore-flavored docstrings, module names, and README prose are welcome. Public API names stay plain (`:RegisterAddon`, not `:WindTheSpring`). When in doubt, pick the word a new user would understand instantly — lore is garnish, not substrate.

## Live-user constraints (critical)

FlipQueue (`FlipQueueDB`) and Tempo (`TempoDB`, `TempoCharDB`) have live users on CurseForge and Wago. Cogworks must **never** claim or rename those SavedVariables. If Cogworks ever needs its own account-wide storage it should use a fresh name (e.g. `CogworksDB`) that doesn't collide with any cog's data.

Similarly, the slash commands `/fq`, `/flipqueue`, `/tempo`, `/tmp`, `/maxcraft`, `/mxc` belong to their cogs. Cogworks should not touch them.

## Release flow

Tagged push → GitHub Actions (`release.yml`) → BigWigsMods packager → CurseForge + Wago.

Version scheme:
- `lib.version` — human-facing semver of the suite ("0.1.0")
- `lib.minorVersion` — LibStub minor; bump on every additive API change

Tag conventions:
- `v0.1.0-alpha1` → alpha channel
- `v0.1.0-beta1` → beta channel
- `v0.1.0` → stable

## Repo layout

```
cogworks/
├── Cogworks-1.0/
│   └── Cogworks-1.0.lua    # the library itself
├── cogworks.toc            # standalone addon manifest (also the build target)
├── .pkgmeta                # packager config
├── .github/workflows/
│   └── release.yml         # BigWigsMods packager pipeline
├── docs/
│   └── PLAN.md             # integration plan for the suite
├── README.md
├── CLAUDE.md
└── LICENSE
```

## Feedback tracking

Player feedback (from the Chronoforge Discord), bug reports, and internal observations are tracked as `.md` files in per-cog `feedback/` directories. Cogworks-library-level issues live in `C:/src/cogworks/feedback/`; per-cog issues live in each cog's own `feedback/`. Schema, lifecycle, and ID format are documented in `~/.chronoforge/CONVENTIONS.md`. Cog → path → idPrefix mapping lives in `~/.chronoforge/config.json`.

Structure per repo:

```
feedback/
├── _TEMPLATE.md
├── collection/   # phase 1 — still gathering info
├── releases/     # phase 2 — scoped to a target version
│   └── v<X.Y.Z>/
└── archive/      # shipped, wontfix, duplicate
```

Slash commands (user-scoped, available from any session): `/feedback-scan`, `/feedback-ingest`, `/feedback-capture`, `/feedback-refresh`, `/feedback-promote`, `/feedback-status`, `/feedback-note`, `/cog-init`.

### Proactive capture

When the user mentions a bug, regression, feature idea, or improvement during normal work, offer to log it via `/feedback-capture` — search for related existing entries first, then augment or create. Don't write a feedback file unprompted; ask first. Similarly, when shipping a fix or trying an approach to resolve a tracked issue, offer to append to its Attempts log via `/feedback-note`.

Commit messages referencing a tracked issue should use `<type>(<ID>): <subject>` — e.g. `fix(COG-004): guard RegisterAddon against nil namespace`.

## When adding new library features

1. **Bump `MINOR`** in `Cogworks-1.0.lua` before adding the feature.
2. **Guard stateful tables** with `lib.foo = lib.foo or {}` so older copies don't clobber newer state when LibStub re-runs the file.
3. **Never remove** a function or event name. If an API is wrong, add a new one alongside and leave the old one as a deprecated thin wrapper.
4. **Document the new feature** in README.md's "What's inside" and add an example to the usage snippet if it's consumer-facing.
5. **Update `lib.version`** only for suite-level releases; `MINOR` is the internal API version that matters to cogs.
