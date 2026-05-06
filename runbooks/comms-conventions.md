# Comms conventions — issue bodies, issue comments, release announcements

> Canonical home for the comms conventions consumed by scribe (the Discord ↔ GitHub bridge). Supersedes scribe's `docs/PLAYER_FACING_CONVENTIONS.md`; scribe's parser code stays in scribe and consumes the conventions defined here. Linked from each cog's `CLAUDE.md`.

How agents (and humans) write GitHub issue bodies, comments, and release notes that reach players cleanly through the scribe Discord ↔ GitHub bridge. **Cogworks is the canonical home for these conventions; scribe is a consumer.** Changes to the conventions happen in the cogworks runbook; scribe's parser updates to match.

## Standards changelog

Cog sessions check the top entry below against their `CLAUDE.md` "Last acknowledged" code for this runbook. If newer, the agent prefixes its first response with `Standards updated:` plus a one-line summary per new entry, then updates the code as part of the session's commit.

- **2026-05-05a** — Initial canonicalization in cogworks. Migrated content from scribe's `docs/PLAYER_FACING_CONVENTIONS.md`. Scribe-side doc remains as historical reference; this is the source of truth going forward.

(Pre-existing entries from scribe's PLAYER_FACING_CONVENTIONS.md changelog are folded into this initial codification — see scribe's history for the prior chronology of the rules below.)

## When to use which heading

Two markdown headings drive scribe's mirroring; both can apply to the same ticket.

| Trigger | Heading | Where |
|---|---|---|
| Shipping a change — committing a fix that references the issue | `## Player summary` | Issue body |
| Communicating with the player during investigation — asking for info, posting status, requesting a debug dump | `## Player update` | Issue comment |

**Player updates do not substitute for a Player summary, and vice versa.** A ticket whose investigation involves Discord conversation AND ends in a deployed fix needs both: Player updates throughout for the conversation, plus a Player summary added to the body before (or as part of) the fix commit so the release-notes draft has something to quote.

A ticket that's purely info-gathering (won't-fix, duplicate, feature spec, debug help) only needs Player updates as appropriate. No Player summary is required because no change is being shipped.

If you commit `fix(<COG>-N): …` and issue N has no `## Player summary` in its body, scribe's release draft lists it under `## ⚠️ No player summary written`. Add the summary to the body and run `/release-redraft` before approving.

## `## Player summary` — issue body

Add this section to a player-visible issue **before closing** it. Scribe pulls the first paragraph into:

- The close announcement posted into the linked Discord thread (the `> quoted` line under the ✅).
- The per-thread followup when a release ships the fix.
- The release draft for the `#releases` channel announcement (compiled across all closed issues for the tag).

**Format:**

```markdown
## Player summary

One short paragraph in plain language — what changed for the player, not what code changed. Keep it to a few sentences.
```

Heading match is case-insensitive. Parser stops at the next markdown heading at any level, then takes the first paragraph (up to the first blank line). If the section is missing or empty, the issue lands in the per-thread followup with no quoted summary — fine, but less useful for the player.

There is no closing-comment fallback. The summary must live in the issue body.

## `## Player update` — issue comment

Add this heading inside a GitHub issue comment when the comment should reach the linked Discord thread. Without it, scribe treats the comment as engineering chatter and doesn't mirror it.

This is the right path **whenever a bot or agent wants feedback from the player on a ticket** — phrasing a question, asking for a `/<cog> debug` → Copy diagnostics dump, requesting a screenshot. Keep the player-facing prompt short and self-contained; engineering context goes below a separator or a different heading and stays on GitHub.

**Format:**

```markdown
## Player update

Full section under this heading goes to the player in Discord — write as much
as you need to. Markdown formatting is preserved, so use lists, line breaks,
and code blocks freely.

To narrow this down, can you do the following:

1. Run `/console scriptProfile 1`
2. Reload your UI
3. Reproduce the slowness for ~30 seconds
4. Run `/<cog> debug` → click Copy diagnostics → paste the output below

If a slash command errors, let us know which step failed.

## Engineering note

Stack traces, hypotheses, links to other tickets — whatever's useful to the next agent reading this issue. Players never see anything below an h1 or h2 heading.
```

Section bound is the next h1 or h2 heading, so `### Steps` or similar inside the player-facing block stay in the player content. Long updates that exceed Discord's 2000-char per-message cap auto-chunk into consecutive messages with a `_(continued)_` marker; nothing is truncated.

### Bot/agent gotchas

- **Author must not be a GitHub bot account.** Scribe filters `sender.type === 'Bot'` *before* checking for the heading — that's the loop guard against scribe mirroring its own transcribed Discord-→-GitHub posts. Posting via `gh` CLI through your PAT works (sender type is `User`). A future GitHub App account would be filtered.
- **Edits don't fire.** Only `action: created` is mirrored. If you edit a comment to add `## Player update` after the fact, it won't reach Discord. Write the heading on the first save.

## Player-facing copy style

Both blocks follow the same voice:

- **Plain language.** No file paths, no symbol names, no acronyms the player wouldn't know.
- **Short.** Two or three sentences is usually right.
- **"What changed for the player" or "what we need from you,"** not "what we did in the code."
- **No bug numbers, PR numbers, or internal IDs** — scribe adds the issue link on its own.
- **Themed sections + short bullet links beat engineering prose** for release notes.

## Cog-side asks for diagnostics

When a bot or agent needs the player to run a debug dump, the standard ask is:

> Run `/<cog> debug` → click Copy diagnostics → paste the output below.

Or for cogs with an About page:

> Open Settings → About → click Copy diagnostics → paste the output below.

`Copy diagnostics` is the **one phrase** that's consistent across all cogs (per `technical-standards.md` rule 6.1). Don't invent cog-specific phrases for the same operation.

## RELEASES.md format compatibility

Scribe consumes per-tag sections from RELEASES.md to draft Discord announcements. The runbook covering RELEASES.md format (`doc-conventions.md`) maintains compatibility with scribe's parser:

- Heading format `## vX.Y.Z[-channelN]` (exact tag) — scribe's first match.
- Falls back to `## vX.Y.Z` (base version with prerelease suffix stripped) — common pattern of one in-development section across an alpha series.
- Falls back to `## Unreleased` — used in stub files until the dev moves the heading.
- Section bound: next h1 or h2 heading. Sub-sub-headings (h3+) preserved.

Any change to RELEASES.md heading format is a coordinated change between this runbook (or `doc-conventions.md`) and scribe's parser. Treat as a `## Standards changelog` entry on both sides.

## Release announcement flow (scribe-side, summarized)

When a cog tags a release:
1. Scribe detects the GitHub release event.
2. Scribe compiles a draft from closed issues whose closing PR's `Closes <COG>-N` reference falls between the previous tag and this one.
3. Each issue's `## Player summary` becomes a bullet in the draft.
4. Issues missing summaries land under `## ⚠️ No player summary written`.
5. Scribe also includes the cog's RELEASES.md section for the new tag.
6. The draft posts to a staging channel for review; `/release-redraft` regenerates after fixes; `/release-publish` (or equivalent) posts to `#releases`.
7. Each closed issue's linked Discord thread gets a per-thread followup confirming the fix is live.

The user-facing surface of this flow stays scribe's responsibility; the *inputs* (per-issue summaries, RELEASES.md sections) are this runbook's responsibility.

## Last exercised

_New runbook; not yet exercised. The conventions themselves have been in production use via scribe's PLAYER_FACING_CONVENTIONS.md._
