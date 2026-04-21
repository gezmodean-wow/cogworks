---
id: COG-003
cog: cogworks
status: investigating
title: Minimap gear-border branding for suite cogs
sources:
  - type: internal
    session: 2026-04-21
    note: Brand identity — make cogs visually distinct from generic circular LDB minimap buttons
reporters: []
created: 2026-04-21
updated: 2026-04-21
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

1. **Investigation** (first action):
   - Read LibDBIcon-1.0 from the installed WoW addons dir to understand the button frame construction + texture API.
   - Verify minimap rotation behavior (camera and map modes) against non-circular button textures by inspecting the Blizzard `Minimap` frame code paths.
   - Stand up a scratch prototype: grab an existing cog's button via `LibDBIcon:GetMinimapButton(...)`, swap its NormalTexture to a placeholder gear-shaped TGA, confirm rendering at default minimap button size. Document findings as an Attempts entry on this issue.
2. **Design the API** — `lib:RegisterCogMinimapButton(addonName, opts)` wrapping `LibDBIcon:Register(addonName, dataobject, savedvarsTable)` plus the texture swap. Decide whether this fully replaces cogs' current LibDBIcon calls or layers on top.
3. **Create the texture asset** — gear-ring 128×128 with transparent teeth. Commit to `Art/minimap-gear-border.tga` (or similar path) in cogworks repo. Probably commissionable or generatable from existing Cogworks branding assets.
4. **Implement in Cogworks** — new MINOR bump. Add to UIShowcase so the effect is visible without needing to test in-game.
5. **Roll out across cogs** — each cog updates its `Core.lua` to call `lib:RegisterCogMinimapButton` instead of `LibDBIcon:Register` directly. One cog at a time for canary testing; **FlipQueue first** (largest live user base means regressions surface fastest).
6. **Document** — short note in cogworks README + each cog's CLAUDE.md that the minimap button chrome is suite-shared and not per-cog customizable by design.
