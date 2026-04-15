# Cogworks — art brief (logo + banner)

This brief is for commissioning or generating the launch art for Cogworks. It's written so an illustrator, AI image tool, or contracted artist can produce all the assets in one pass without follow-up clarification.

---

## Concept in one sentence

A **brass clockwork mainspring** — the central wound coil of a mechanical movement — rendered against a dark background, with a subtle **arcane-purple energy glow** seeping through the gaps between the coils, suggesting that this clockwork runs on time magic.

---

## Why this concept

Cogworks is the *mainspring* of the suite — that's the literal metaphor in every doc, every README, and the launch copy. The mainspring is the part of a mechanical watch that stores the energy that drives every other gear. Visually it's distinctive, immediately reads as "clockwork without being a generic gear," and it leaves room for the chronomancy / time-magic flavor that runs through the rest of the brand.

The arcane-purple glow is the visual signature of the suite — it's reserved in-game for "time magic" moments (reset-soon warnings, profit surges) and should be present but **subtle** in the logo, not the dominant color. Brass and gold lead; purple highlights.

---

## Palette (use these exact hex values)

These come straight from `lib.Theme` in `Cogworks-1.0/Cogworks-1.0.lua`:

| Role | Hex | RGB | Notes |
|---|---|---|---|
| Primary background | `#14141F` | 20, 20, 31 | The dark base of the entire suite |
| Panel background | `#1F1F29` | 31, 31, 41 | Slightly lighter for depth |
| Inset / deep shadow | `#0A0A12` | 10, 10, 18 | Behind the mainspring |
| Brass (clockwork trim) | `#D4A017` | 212, 160, 23 | The mainspring itself — primary color |
| Gold (accent) | `#FFD100` | 255, 209, 0 | Highlights on the brightest edges of the spring |
| Arcane purple | `#8B5CF6` | 139, 92, 246 | The energy glow leaking through the coils |
| Border | `#4D4D66` | 77, 77, 102 | Outer frame, if used |

**Color discipline:** brass and gold are the dominant 70%. Dark background is 20%. Arcane purple is the remaining 10% — a glow, not a flood. If the purple is the first thing the eye lands on, it's too much.

---

## Required assets

All assets should be delivered as **transparent PNG** unless otherwise noted, plus the **source file** (SVG, AI, PSD, or Figma) for future edits.

| Asset | Size | Purpose | Notes |
|---|---|---|---|
| **Square logo** | 512×512 | CurseForge avatar, Wago logo, Discord server icon | Mainspring centered, slight padding |
| **Square logo (small)** | 256×256 | Wago, in-game tooltip icon, README header | Must remain legible — simplify detail if needed |
| **Square logo (tiny)** | 64×64 | LDB icon, minimap button if cogs ever surface one | Heavy simplification — the silhouette has to read at this size |
| **CurseForge thumbnail** | 400×200 | Search result card | Logo on the left, "Cogworks" wordmark on the right |
| **GitHub social card** | 1280×640 | OpenGraph preview when the repo URL is shared | Logo + "Cogworks" wordmark + tagline "The mainspring of the Cogworks suite" |
| **Wide banner** | 1920×480 | Discord channel banner, future website hero | Logo offset left, wordmark + tagline right, plenty of negative space |

---

## Wordmark

When the word "Cogworks" appears alongside the mark:

- **Typeface:** a clean modern serif or slab serif — something with weight and presence, not ornate fantasy lettering. Think *Cinzel*, *Cormorant Garamond Bold*, or *Marcellus*. Avoid Papyrus and avoid over-the-top WoW-style scripts.
- **Color:** brass `#D4A017` for the wordmark, with the gold `#FFD100` reserved for a single highlight stroke or the dot of a letter.
- **Tagline (when used):** "The mainspring of the suite" in muted gray `#8C8C99`, smaller, set below the wordmark.

---

## What to avoid

- **Generic spur gears.** Every addon library uses a gear logo. The mainspring coil is the whole point — it's distinctive precisely because nobody else uses it.
- **Steampunk overload.** No rivets, no copper pipes, no Victorian filigree. The vibe is *precision instrument*, not *steampunk costume*.
- **Heavy purple.** The arcane glow is a seasoning, not the main course. If you squint and the logo reads purple, dial it back.
- **Fantasy script wordmark.** Cogworks is a developer tool with a lore garnish, not a high-fantasy raid addon.
- **Drop shadows on a transparent background.** Make sure the logo works on both the dark suite background `#14141F` and on a white CurseForge listing card.

---

## Reference touchpoints

- The visible mainspring of an exposed mechanical watch movement (search "watch mainspring barrel exploded view")
- TSM4's dark-with-gold accent UI palette (for the overall mood, not the logo style)
- The arcane-purple highlight color is the same one used in the rest of the suite UI — `#8b5cf6`, the standard Tailwind violet-500

---

## Delivery checklist

- [ ] All six PNG sizes above, transparent background
- [ ] Source file (SVG preferred, since the logo is geometric)
- [ ] A "logo on dark background" preview rendered against `#14141F`
- [ ] A "logo on light background" preview rendered against `#FFFFFF`
- [ ] The 64×64 silhouette test — does it still read as a mainspring at icon size?

Once delivered, drop the assets into `docs/branding/` in this repo and update the CurseForge + Wago listings.
