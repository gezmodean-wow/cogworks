# Chronoforge Discord — Cogworks launch announcement

> Short, punchy, designed to drop into the Chronoforge announcements channel. Use the version with the embedded image once the logo is finalized.

---

## Version A — short (announcements channel)

> ⚙️ **Cogworks v0.1.0 is live.**
>
> The mainspring of the suite — the shared library that lets FlipQueue, Tempo, Maxcraft, and the upcoming ledger cog tick to the same rhythm. Event bus, theme, character keys, addon registry, all in ~230 lines of Lua.
>
> If you already use FlipQueue or Tempo, you'll get Cogworks automatically with their next update — nothing to install. If you're a developer building your own cog, you can embed it via `.pkgmeta`.
>
> 📦 CurseForge: <link>
> 📦 Wago: <link>
> 🔧 Source: https://github.com/gezmodean-wow/cogworks
>
> Questions, ideas, or "what should this event be called?" debates → drop them in #cogworks-dev.

---

## Version B — longer (changelog channel or pinned post)

> ⚙️ **Cogworks v0.1.0 — the mainspring is wound.**
>
> Cogworks is the shared core library for the Cogworks suite. It's the piece that makes the cogs feel like one project instead of three unrelated addons.
>
> **What it gives every cog:**
> • A shared event bus — FlipQueue can react to a Tempo reset, the ledger can react to a FlipQueue sale, no hard dependencies between any of them
> • A shared theme — dark base, gold accents, the arcane-purple highlight reserved for "time magic" moments
> • Canonical `"Name-Realm"` character keys that match Syndicator's convention, so all suite data shares one keyspace
> • An addon registry, so any cog can enumerate its installed siblings for an About panel or cross-promotion
> • A Syndicator capability bridge for cogs that want to opportunistically enrich their data
>
> **What it deliberately doesn't do:**
> • Touch any cog's SavedVariables (FlipQueueDB, TempoDB, etc. are off-limits)
> • Provide gameplay features of its own
> • Break old APIs — Cogworks is **additive only**, every release just adds, nothing ever disappears
>
> **Do you need to install it?** Probably not. It's embedded into every cog that uses it. The standalone CurseForge/Wago install is for developers and the curious — it adds a `/cogworks` slash command for poking at the library, and that's it.
>
> 📦 CurseForge: <link>
> 📦 Wago: <link>
> 🔧 Source + issues: https://github.com/gezmodean-wow/cogworks
> 📜 Scope doc (Cogworks vs. individual cogs): https://github.com/gezmodean-wow/cogworks/blob/main/docs/launch/scope.md
>
> Building your own cog and want to embed Cogworks? The README has a copy-paste `.pkgmeta` snippet. Pop into #cogworks-dev if you hit anything weird.
