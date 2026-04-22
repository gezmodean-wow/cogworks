---
id: COG-003
cog: cogworks
status: in-progress
title: Minimap gear-border branding for suite cogs
sources:
  - type: internal
    session: 2026-04-21
    note: Brand identity — make cogs visually distinct from generic circular LDB minimap buttons
reporters: []
created: 2026-04-21
updated: 2026-04-21
investigation_complete: true
release: null
tags: [minimap, branding, libdbicon, ui, art]
---

## Summary

Replace the default circular minimap-button border used by LibDBIcon with a gear-shaped border for all Chronoforge suite cogs. Creates a consistent visual identity — players recognize a gear ring on their minimap as "a Gezmodean cog" rather than a generic third-party addon. Ships as a shared Cogworks entry point (`lib:RegisterCogMinimapButton(addonName, opts)`) so all five cogs get the effect with a single call.

## Reproduction

Current state:

- All cogs (and Cogworks standalone) use LibDBIcon's default circular button chrome.
- Visually indistinguishable from the hundreds of other LDB-registered addons on a typical user's minimap.
- No suite-level brand cue on the most visible addon surface the game offers.

Desired state:

- All Chronoforge cogs appear with a gear-shaped outer ring (transparent teeth, solid inner core) around their addon icon.
- Single API entry point in Cogworks for consistency and future evolution (animations, theme-aware coloring, etc.).
- Backward-compatible with LibDBIcon-aware users (minimap-icon-disable toggles still work).

## Attempts

- **2026-04-21**: Roadmap captured. Feasibility investigation pending — see Next steps.

- **2026-04-21**: **Investigation complete — feasibility confirmed**, all four questions answered from reading LibDBIcon-1.0 v56 (`AddOns/BugSack/Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua`). No prototype in-game session needed for feasibility; can proceed directly to API design + texture asset.
  - **Q1 (button exposure)**: Fully exposed. `lib:GetMinimapButton(name)` returns the button frame; button has `.border`, `.background`, `.icon` textures as fields. Better still, LibDBIcon ships a **dedicated border API** — `lib:SetButtonBorder(name, borderTexture, size, framePoint, offsetX, offsetY)` (line 509). Swaps the border texture with one call. There's also a `LibDBIcon_IconCreated` callback fired after button creation (line 315) for deferred registration.
  - **Q2 (minimap rotation)**: No concern. Buttons are child frames of `Minimap` positioned via `SetPoint("CENTER", Minimap, "CENTER", x, y)` at a calculated angle around the rim. The `rotateMinimap` cvar rotates the map *contents texture*, not child Button frames. A gear border will stay visually upright regardless of camera/map rotation. Confirmed across round and square minimap modes (the shape table at lines 138–153 only affects positioning on corners vs sides, never the button's own rendering).
  - **Q3 (mask clipping)**: No concern. Addon buttons render outside the minimap's content mask — they're siblings positioned on the rim with `lib.radius` (default 5) extending past the minimap edge. The circular mask applies only to the map texture, not to child Button frames. Round and square minimaps both render custom borders fully.
  - **Q4 (texture format + sizing)**: Target **128×128 TGA with alpha channel**, displayed at 50×50 (matches LibDBIcon's default border size on mainline, line 534). Defaults for reference: button frame 31×31 (line 483), icon 18×18 (line 608), border 50×50 extending outward. 128×128 source gives ~2.5x headroom for 1.5x UI scale (75×75 displayed). BLP would be Blizzard-native/optimal but TGA is simpler to author and ships fine via BigWigsMods packager.

- **2026-04-21**: **API design confirmed trivial**. Given LibDBIcon's existing `SetButtonBorder`, the Cogworks wrapper is ~10 lines — register with LibDBIcon, call SetButtonBorder pointing at `Interface\AddOns\Cogworks\Art\CogBorder.tga`. Optional extension: also customize `SetButtonHighlightTexture` for a gear-shaped hover highlight (nice-to-have, defer).

- **2026-04-21**: **Two bonus findings worth noting**:
  - **AddonCompartmentFrame support** (LibDBIcon lines 312, 637): modern users increasingly pin addon icons to Blizzard's compartment dropdown rather than the minimap itself. The compartment uses only the inner icon (no border), so our gear-ring doesn't apply there. No work needed — compartment flow passes through LibDBIcon's existing path intact. But worth knowing: our branding doesn't reach compartment users; they'll still see a normal icon list. If important, consider a future sub-issue for compartment-specific branding (e.g. prefixing the entry text with "⚙ " or similar).
  - **Existing `SetButtonBackground`** (line 549) is also available if we want to customize the backdrop disc *behind* the icon — could be used to paint a subtle brass-gold tone to reinforce the gear aesthetic without changing the border shape. Consider for v2.

- **2026-04-21**: **Gear texture asset received** and placed at `C:/src/cogworks/Art/CogBorder.tga` (128×128, TGA, ~26 KB RLE-compressed). Sourced from `C:/Users/gezmo/Downloads/gear.tga`. Art dir created at repo root. `.pkgmeta` ignore list does not include `Art/`, so the TGA will ship in the packager output as `Interface\AddOns\Cogworks\Art\CogBorder.tga`. File sits unused in the package until the `RegisterCogMinimapButton` wrapper references it — shipping the asset alone is a no-op for users' current behavior.

## Notes

### Investigation questions (drive the first Attempts entry)

1. **LibDBIcon button exposure** — does LibDBIcon expose the minimap button frame so its NormalTexture / PushedTexture / HighlightTexture can be swapped? Expected yes via `LibDBIcon:GetMinimapButton(name)` or equivalent; confirm by reading the installed LibDBIcon code at `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\` (most cogs include it in their Libs/ folder).
2. **Minimap rotation** — when the player has camera/map rotation enabled, does the rotation apply only to the map contents or also to addon buttons anchored to the minimap frame? Expected: only map contents — buttons are fixed relative to the minimap frame — but needs verification in both round and square minimap modes.
3. **Minimap mask clipping** — does Blizzard's minimap circular mask clip non-circular button borders when the player uses the default round-minimap style? Potential visual glitch — if so, need to parent the gear-texture outside the masked region or use an alpha-mask approach.
4. **Texture format + resolution** — what format (TGA vs BLP) and resolution (32×32 / 64×64 / 128×128) produces a crisp gear at typical minimap button display size (~18×18 pixels)? Stress-test at both 0.7x and 1.5x UI scales.

### Consumers (all five)

- Cogworks standalone
- FlipQueue
- Tempo
- Maxcraft
- Tally

### Design considerations

- **Consistency across cogs** — single shared gear texture, not per-cog variants. Brand identity comes from the shape; per-cog differentiation is the inner icon art, not the chrome.
- **Inner icon remains cog-specific** — each cog's icon art stays inside the gear ring. Don't merge the border and icon into a single texture; keep them composable so cogs can change their icon without re-authoring the ring.
- **Backward-compatible** — if a user disables the minimap icon in cog settings, behavior matches current LibDBIcon behavior. Don't regress existing minimap-hide toggle.
- **Texture asset location** — 128×128 gear-ring texture (transparent outside + teeth cutouts). Commit to `Art/minimap-gear-border.tga` or similar in the cogworks repo so all cogs pull it from the Cogworks external at package time.

### Out of scope for this issue

- Replacing the inner icon with a gear motif — that's per-cog art direction; tracked separately if desired.
- Animating the gear (rotation on hover, spin on click) — nice-to-have, defer.
- Alternative shapes for a "library"-kind cog (Cogworks itself may want a distinct variant) — revisit if needed.

## Next steps

Investigation complete — feasibility confirmed, implementation path is clear. Remaining work:

1. **Create the gear-ring texture asset** — 128×128 32-bit TGA with alpha. Solid inner ring, transparent gear-teeth cutouts on the outer edge, transparent center (so the cog's inner icon shows through). Commit to `Art/CogBorder.tga` in the cogworks repo. Either author manually, re-use existing Cogworks branding art (there's a 400×400 logo at `docs/branding/cogworks-logo-400.png`), or commission.
2. **Implement `lib:RegisterCogMinimapButton(addonName, dataobject, savedvars)`** — wraps `LibDBIcon:Register(...)` plus `LibDBIcon:SetButtonBorder(addonName, "Interface\\AddOns\\Cogworks\\Art\\CogBorder", 50, "TOPLEFT", 0, 0)`. Additive on Cogworks; new MINOR bump. Guard with `LibStub("LibDBIcon-1.0", true)` presence check + clean error via `PrintError` if absent.
3. **Add to UIShowcase** — demonstration panel showing the gear-bordered button so the effect is visible without needing to test in-game. (Minimap buttons only exist on the real minimap, so the showcase would be a static render: icon + gear-ring as an illustrative composition.)
4. **Roll out across cogs** — each cog's `Core.lua` swaps `LibDBIcon:Register(...)` for `Cogworks:RegisterCogMinimapButton(...)`. Order for canary:
   - **FlipQueue first** (largest live user base — regressions surface fastest; the existing LDB icon code is well-understood)
   - Tempo second
   - Maxcraft / Tally last (pre-release / not yet shipped — safer to bundle with initial release)
   - Cogworks standalone updates its own call last so the library ships before its consumer updates
5. **Document** — short note in cogworks README ("all Chronoforge cogs share the gear-bordered minimap icon via `Cogworks:RegisterCogMinimapButton`") and in each cog's `CLAUDE.md` that the minimap button chrome is suite-shared and not per-cog customizable by design.
6. **v2 ideas (defer, track separately if desired)**:
   - Gear-shaped highlight texture (`SetButtonHighlightTexture`) for hover.
   - Brass-gold background disc behind the icon (`SetButtonBackground`).
   - Compartment-flow branding (prefix compartment entry text with a glyph since the gear-border doesn't apply to AddonCompartmentFrame).
