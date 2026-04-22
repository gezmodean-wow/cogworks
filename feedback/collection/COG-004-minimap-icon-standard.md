---
id: COG-004
cog: cogworks
status: investigating
title: Minimap icon readability standard for suite cogs
sources:
  - type: internal
    session: 2026-04-21
    note: Existing per-cog icons are too detailed to read at 18x18 minimap display; they become indistinguishable colored blobs. Need a suite-wide standard for the INNER icon content that pairs with COG-003's gear-border chrome.
reporters: []
created: 2026-04-21
updated: 2026-04-21
release: null
tags: [minimap, branding, ui, art, icons, standard]
---

## Summary

Current per-cog minimap icons are detailed fantasy-style illustrations (ornate frames + multiple internal elements + layered effects). Beautiful at 400×400 on a CurseForge page; unreadable at 18×18 on the minimap. Establish a suite-wide standard for the INNER icon content so each cog is instantly identifiable from a glance, while COG-003's gear-border handles the shared suite identity on the outside.

## Reproduction

Observed 2026-04-21 across all five icons:
- **Cogworks** (`asset_DnJssrLGFUGQNPucwkmj2u8n_*.png`): brass ratchet gear + purple pawl + hub + texture. Pawl invisible at 18×18; reads as "a gear".
- **FlipQueue** (`flipqueue-icon.png`): gold frame + F + Q + arrow-loops + blue lightning. Letters lost in electrical effect at small sizes.
- **Tempo** (`tempo-icon.png`): dark-blue frame + clock face + arrow + rune border + checkmark + X. The most detailed of the five; reads as "dark blue blob".
- **Maxcraft** (`asset_PU8PFcuaWqn9ewiVMETW2YSM_*.png`): gear-shaped frame + crossed hammers + lightning + text. Hammers survive but barely.
- **Tally** (`tally.png`): ornate frame + four rows of crystals / runes / gears / checkmarks. Reads as "ornate dark square".

Shared failure modes:
- Too many competing elements — no single focal point.
- Low foreground/background contrast — dark-on-dark or medium-on-dark.
- Shared palette (deep blue/purple + gold) — icons look like variations of the same thing.
- No silhouette distinction — squint test fails.

## Attempts

- **2026-04-21**: Problem catalogued. Design standard proposed (see Notes). No icon revisions authored yet — awaiting the user to generate and iterate.

- **2026-04-21**: **v1 candidates received** — user generated all five inner icons as PNG: `cw-inner.png`, `fq-inner.png`, `tm-inner.png`, `mc-inner.png`, `tl-inner.png`. Sourced into `cogworks/Art/inner/` (added to `.pkgmeta` ignore — source-only, not shipped). Visual evaluation: **all five pass the squint test**. Bold sans-serif letters, flat solid backgrounds, consistent design system (same composition / weight / padding across the family). Foreground/background pairs per spec with one small drift: CW background reads as warm brown rather than the spec'd deep brass `#3A2A0A` — distinctive and arguably better for the "suite hub" feel, keep as-is. TM and TL both use navy backgrounds but distinct foreground hues (violet vs teal) keep them side-by-side distinguishable. Transparent outer area is clean — will layer inside COG-003's gear-border with no ring/disc color clash.

- **2026-04-21**: **Remaining gap before in-game integration**: PNG → TGA (or BLP) conversion. WoW client does not load PNG as a texture. Conversion produces `<cog>-inner.tga` files that go into each cog's own `Art/` directory (distribution step deferred to a follow-up pass).

- **2026-04-21**: **v1 TGAs received and distributed.** User converted all five PNG sources to TGA (30–45 KB each, ~95% compression from the ~1 MB PNG sources). Valid TRUEVISION-XFILE headers confirmed. Source archive stays at `cogworks/Art/inner/*.tga` (alongside the PNG masters; both gitignored from packaging via `.pkgmeta` ignore). Ship-ready copies distributed to each cog's own `Art/` folder:
  - `cogworks/Art/cw-inner.tga`
  - `flipqueue/Art/fq-inner.tga`
  - `tempo/Art/tm-inner.tga`
  - `maxcraft/Art/mc-inner.tga`
  - `tally/Art/tl-inner.tga` (new `tally/Art/` dir created)
  The distributed TGAs ship at `Interface\AddOns\<Cog>\Art\<cog>-inner.tga` in each cog's package. **Still unreferenced by code** — no behavior change until each cog's icon-registration call points at the new TGA (pending the COG-003 `RegisterCogMinimapButton` wrapper).

- **2026-04-21**: **COG-003 wrapper shipped** as cogworks v0.6.0 — `lib:RegisterCogMinimapButton(addonName, dataobject, savedvars)` is now available to consuming cogs. Per-cog rollout unblocked: FlipQueue canary first, then Tempo, then Maxcraft. Each cog's `Core.lua` minimap block updates to call `Cogworks:RegisterCogMinimapButton` passing `icon = "Interface\\AddOns\\<Cog>\\Art\\<cog>-inner"` as the dataobject icon path. When a cog ships its first release using the new wrapper, both COG-003 (gear border) AND COG-004 (inner icon) go live in the same visual change.

## Notes

### Design principles (the readability bar)

Every suite minimap icon must satisfy:

1. **One focal element** — a single letter, glyph, or shape. No compositions.
2. **Silhouette-first** — squint test: the outline alone should communicate which cog this is.
3. **Two-color contrast** — one strong foreground on one solid background. No gradients, no effects, no textures.
4. **Distinct per-cog hue** — color alone must disambiguate when two cog buttons sit next to each other on the minimap.
5. **Suite cohesion handled externally** — COG-003's gear-border texture provides the "this is a Chronoforge cog" signal. The inner icon only needs to answer "which one".

### Approaches considered

| Option | Description | Verdict |
|---|---|---|
| A. Bold monogram + signature color | 2-letter thick sans-serif on solid color block | **Recommended** — letters outperform glyphs for specificity; matches the ID prefix system |
| B. Function-symbol glyphs | Gear / arrow-loop / anvil / hourglass / tally-marks | Deferred — risks "all look like a round filled shape" at 18×18 without weeks of iteration |
| C. Color-only abstraction | Same glyph everywhere, differ by color | Rejected — zero per-cog identity without tooltip |
| D. Hybrid (letter + faint function watermark) | A's monogram foreground + B's glyph at 20% opacity behind | **v2 polish** — adds character at tooltip/promo sizes, dissolves at 18×18 without hurting readability |

### Standard spec (Approach A)

**Canvas**: 128×128 TGA with alpha. Inner icon content fills a circular area; outer gear-border from COG-003 frames it.

**Typography**: geometric sans-serif, **extra-bold** weight, **70%** of canvas height, dead-centered. No italic, no serifs, no outline, no drop shadow. Letters rendered as flat color (no gradient). Candidate typefaces: Orbitron, Rubik (extra-bold), Inter (black weight), or equivalent geometric-humanist sans.

**Per-cog spec:**

| Cog | Monogram | Foreground | Background | Rationale |
|---|---|---|---|---|
| Cogworks | **CW** | Gold `#FFD100` | Deep brass `#3A2A0A` | Matches existing brand palette; the "center" of the suite |
| FlipQueue | **FQ** | Gold `#FFD700` | Deep purple `#2A0D3A` | AH epic-quality purple + coin gold |
| Maxcraft | **MC** | Burnt orange `#FF7020` | Deep steel `#1A2028` | Forge / anvil heat against cold metal |
| Tempo | **TM** | Arcane `#8B5CF6` | Midnight `#0D1530` | Matches existing `Theme.arcane` in Cogworks-1.0.lua |
| Tally | **TL** | Teal `#14B8A6` | Deep ink `#0A1020` | Ledger / counting / accountant's green-teal |

**Monogram rationale**: 2-letter monograms chosen over single letters to avoid the Tempo/Tally "T" collision, and because 2 bold letters at 70% canvas height still read cleanly at 18×18 (roughly 12×6 pixels per letter — legible for geometric sans). Monograms mirror the feedback ID prefixes used for tracked-issue IDs (COG / FQ / MXC / TMP / TLY) so naming and visual systems stay aligned. The T-cogs are shortened to `TM` and `TL` for visual compactness.

**Background**: solid color fills the circular area. NO ornate frame, NO lightning, NO runes, NO embossed texture — the gear-border provides the decorative shape externally. Interior stays minimalist.

### Image-generation prompt template

For AI-tool iteration (copy, swap letter + colors per cog):

> *Minimalist icon, 128×128 square, transparent canvas. Two bold sans-serif letters `"FQ"` in deep gold (`#FFD700`), extra-bold weight, 70% canvas height, perfectly centered on a solid deep purple (`#2A0D3A`) circular disc filling the canvas. Flat design, no gradients, no texture, no effects, no outline, no drop shadow. High contrast. Designed to be legible at 18×18 pixels.*

Run each, export as TGA with alpha, screenshot and aggressively downsample to 18×18 to verify the squint test passes.

### Out of scope for this issue

- **The gear-border chrome itself** — tracked separately as COG-003.
- **Tooltip / promo / CurseForge page icons** — those can stay as the existing detailed illustrations, or get a separate larger variant. The scope here is specifically the minimap button interior.
- **Icon style for the Addon Compartment frame** — compartments display just the icon (no gear-border), and the monogram design works there at slightly larger sizes too. If compartment-specific treatment is ever needed, that's v2.
- **Animations** (hover pulse, active-state glow) — v2 polish, defer.

## Next steps

1. **Generate v1 candidates** — run the prompt template above with each per-cog color pair. Export 128×128 PNG/TGA for each.
2. **Squint-test all five** — paste the five candidates onto a simulated minimap background (dark map pixels), downsample to 18×18, confirm each reads correctly AND the five are mutually distinguishable side-by-side.
3. **Compose with COG-003 gear-border** — layer the monogram icon with the planned gear-ring texture; verify the interior color doesn't fight with the brass gear color. May need to adjust background hues if contrast is poor.
4. **Cross-reference Cogworks theme keys** — `Theme.gold`, `Theme.arcane`, `Theme.brass` etc. are defined in `Cogworks-1.0.lua`. Where possible, align per-cog icon colors with suite theme values so a future "dynamic-color icon" feature could tint icons from live theme settings.
5. **Commit to `Art/` folders** — once approved, drop TGA files into each cog's `Art/` directory with consistent naming: `<cog>-minimap-icon.tga`. Update each cog's TOC/Core.lua reference.
6. **Retire the old illustration icons** — either delete or archive as the CurseForge-page icons. Tooltip previews and showcase can also use the new simpler icons; reduces asset count across the suite.
7. **Document the standard** — short section in cogworks README + CLAUDE.md that the minimap icon spec is shared. Reference this issue's spec table so future cogs follow the standard.

### Blocks on / unblocks

- **Blocks**: COG-003 rollout quality — the gear-border looks underwhelming if the inner icon is still a detailed blob. Ideally ship COG-004 icons alongside COG-003 gear-border so players see the combined effect on first deploy, not a two-stage visual change.
- **Unblocks**: none directly — but aligning with theme color keys (step 4) makes future dynamic-tint features trivial if we ever go there.
