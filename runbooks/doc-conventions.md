# Documentation conventions


Conventions for the two changelog files every cog maintains. **Issue-body and issue-comment conventions** (`## Player summary`, `## Player update`) live in `comms-conventions.md`; this runbook covers the file artifacts only.

## Standards changelog

- **2026-05-05a** — Initial. Cogworks no longer exempt from RELEASES.md (each cog stands on its own as a self-contained addon).

## File layout

| Repo | RELEASES.md | CHANGELOG.md | Notes |
|---|---|---|---|
| flipqueue | required | required | shipping cog |
| tally | required | required | shipping cog |
| tempo | required | **gap — needs creation on next session** | shipping cog (dormant) |
| maxcraft | required at first tag | required at first tag | pre-release |
| cogworks | required | required | library + standalone addon; each ships independently |

## RELEASES.md — player-facing

Plain language, organized by what players see and do. No file paths, no internal IDs, no commit references. This file is read on CurseForge and Wago project pages, by players reporting bugs, and by the user when reviewing what's about to ship.

**Header** — every shipping cog's RELEASES.md starts with the same preamble (copy verbatim when creating one):

```markdown
# <Cog> release notes

This file is the **player-facing** changelog. It's what shows up on CurseForge and Wago project pages. Plain language, organized by what players see and do — no file paths, no internal terminology, no commit references.

The engineering-detail companion lives in `CHANGELOG.md` (commit-readerese — file:line, internal jargon, full alpha-by-alpha breakdown). When working on <Cog>, update both: `CHANGELOG.md` for the engineering record, this file for the player surface.

---
```

**Per-tag section format:**

```markdown
## vX.Y.Z[-channelN]

One- or two-sentence intro for the release.

### Themed heading (player-readable)

Prose paragraph. What changed, why a player would care, what they need to do (if anything).

### Another themed heading

…
```

Themed headings group player-visible changes — not engineering categories. Examples from existing notes: "Logout is fast again", "German EU buy tasks with prices like `2.000g`: parser handles hidden characters", "Bag clicks broken in raids / after pet battles: hardened".

**Unreleased section:** every RELEASES.md keeps an `## Unreleased` heading at the top. Merging a PR appends draft notes there. Tagging promotes `Unreleased` → `vX.Y.Z[-channelN]` and re-creates an empty Unreleased above it.

## CHANGELOG.md — engineering log

Internal IDs, file:line references, full alpha-by-alpha breakdown. Read by future-you, by agents triaging follow-up bugs, and by the user when reviewing what shipped.

**Heading format (standardized across all cogs):**

```markdown
## [vX.Y.Z[-channelN]] — YYYY-MM-DD — Short title
```

Three components:
- `[vX.Y.Z…]` — version, in brackets (Keep-a-Changelog style)
- `YYYY-MM-DD` — date the tag was cut
- `Short title` — one-line summary, the thing you'd scan for when grepping later

Example: `## [v0.13.2] — 2026-05-05 — Critical: StaticPopupDialogs taint hotfix (COG-30)`

**Sub-section structure:**

```markdown
## [vX.Y.Z…] — YYYY-MM-DD — Title

Brief intro paragraph (one or two sentences) explaining the shape of this release.

### Player summary

One or two prose paragraphs in player English. **This is the source paragraph for RELEASES.md** — write it once here, lift / lightly rework into RELEASES.md's themed sections.

### Fixed | Added | Changed | Removed | Notes

Engineering bullets. Include:
- Internal IDs (`TLY-50`, `COG-30`, `#155`)
- file:line references (`UI/MiniView.lua:1351-1372`)
- Why the change — root cause, not just symptom
- Migration / compatibility notes

### Files (optional)

Optional `git status -s`-style block showing files touched. Useful for big releases.
```

**Unreleased section:** every CHANGELOG keeps a `## [Unreleased]` heading at the top. Same lifecycle as RELEASES.md.

## Lifecycle — when each file gets touched

- **On PR merge:** the merging PR has already updated both files' `Unreleased` sections. PR template's self-review checklist enforces this.
- **On tag:** the pre-tag script (F4 / F5) verifies the tag's section exists. The `Unreleased` → `vX.Y.Z…` rename happens *before* tagging, in the tagging PR (or as an explicit pre-tag commit).
- **On hotfix:** same flow; the hotfix's PR appends to Unreleased, then the patch tag promotes.

## Issue-body conventions (input to docs)

Every code change links to an issue. `Closes <ID>` in the merging PR auto-populates that section's CHANGELOG entry. The structured issue body fields are what an agent reads to act without round-tripping for context.

**Bug template** — see `templates/bug-issue.md`. Required fields: steps to reproduce, expected, actual, environment, severity.

**Task template** — see `templates/task-issue.md`. Required fields: goal, acceptance criteria, out of scope.

For player reports mirrored from Discord via scribe (which arrive as raw text), the eng comment that triages them should fill in the missing fields, or `needs-info` back to the reporter.

## Cross-references

- **RELEASES.md** does not reference issue IDs (player audience doesn't care).
- **CHANGELOG.md** references issue IDs liberally, in the form players-reading-the-code expect: `(COG-30)`, `(#155)`, `(TLY-50)`. Repo prefix when crossing cogs (e.g. flipqueue's CHANGELOG referencing `COG-30` — explicit). Issue-internal `#N` for same-cog refs.
- **PR descriptions** include the linked issue at the top: `Closes COG-30` or `Refs TLY-50`.
- **Commit messages** mirror PR titles (squash-merge does this automatically with sensible defaults).

## What's exempt

- `chronoforge/` itself (this directory) — coordinator workspace, internal-only, no shipping artifact. Runbook updates appended via the `## Last exercised` convention from `CLAUDE.md`.

## Scribe parser compatibility

Scribe (the Discord ↔ GitHub bridge) consumes per-tag sections from RELEASES.md to draft Discord announcements. The format above is what scribe's parser expects. If any change to RELEASES.md heading format is proposed, treat it as a coordinated change between this runbook and scribe's parser — append to both `## Standards changelog` sections.

Specifically scribe expects (in priority order):
1. Exact tag heading: `## v0.12.0-alpha9`
2. Base-version fallback: `## v0.12.0` (with prerelease suffix stripped)
3. `## Unreleased` fallback (used while a release is in development)

Sub-headings (h3+) inside the section are preserved by scribe's chunker. h1 and h2 are section bounds.

## Cross-references

- **Player-facing copy** in RELEASES.md sections follows the voice rules in `comms-conventions.md` (plain language, no internal IDs, themed sections + bullets beat engineering prose).
- **Issue body `## Player summary`** is the canonical source for the player-facing prose. The same paragraph may be lifted into RELEASES.md's themed section for the tag.
- **CHANGELOG.md** can reference internal IDs liberally; RELEASES.md never does (scribe adds the issue link separately).

## Last exercised

_New runbook; not yet exercised._
