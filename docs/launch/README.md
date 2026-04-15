# Cogworks launch packet

Everything needed to publish Cogworks v0.1.0 to GitHub, CurseForge, and Wago, plus the announcement and art assets.

## Files

| File | What it is |
|---|---|
| [`scope.md`](scope.md) | The clear "what's in Cogworks vs. the individual cogs" definition. Link to this from the CurseForge / Wago listings so users don't mistake the standalone install for a feature addon. |
| [`curseforge.md`](curseforge.md) | Long + short description copy for the CurseForge listing, plus project metadata and the screenshot list. |
| [`wago.md`](wago.md) | Same content tuned for the Wago listing. |
| [`discord_announcement.md`](discord_announcement.md) | Two versions of the Chronoforge launch post — short for #announcements, longer for #changelog. |
| [`art_brief.md`](art_brief.md) | Brief for commissioning the logo + banner. Includes exact palette, all required sizes, and a list of what to avoid. |

## Launch checklist

1. **GitHub** — push the repo (done as part of the v0.1.0 prep).
2. **CurseForge** — create the `cogworks` project under the `gezmodean-wow` author. Paste in `curseforge.md`. Add the `CF_API_KEY` repo secret on GitHub.
3. **Wago** — create the `cogworks` project. Paste in `wago.md`. Add the `WAGO_API_TOKEN` repo secret on GitHub.
4. **Art** — commission or generate the assets per `art_brief.md`. Drop the finals in `docs/branding/`. Update both listings.
5. **Tag the release** — `git tag v0.1.0-alpha1 && git push --tags`. The BigWigs packager workflow at `.github/workflows/release.yml` will build and upload to both portals automatically.
6. **Announce** — post `discord_announcement.md` (Version A) in #announcements once the listings are live.
7. **Embed in cogs** — bump FlipQueue and Tempo to embed `Cogworks-1.0` via `.pkgmeta`. Their next release will silently include it.
