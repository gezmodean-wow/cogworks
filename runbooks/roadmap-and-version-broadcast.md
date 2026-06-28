# Runbook: roadmap & version broadcast

> **Status: adopted (2026-06-27).** Canonical home — migrated from `chronoforge/runbooks/` to `cogworks/runbooks/` per cogworks#47 (CF-9). Linked from each cog's and scribe's `CLAUDE.md` — same pattern as comms-conventions.md. The chronoforge draft is removed under CF-9.

How player-visible work reaches Discord *before* it ships, in addition to the existing post-release announcements. **GitHub milestones are the source of truth.** Each triaged issue gets a milestone; scribe broadcasts the resulting state into Discord as (a) a per-issue thread notification when an issue's milestone changes, and (b) pinned roadmap messages in each cog channel plus an aggregate `#roadmap` channel. No microsite, no GitHub Project required.

## Standards changelog

Scribe consumes the milestone-event semantics defined here. Cog and scribe sessions check the top entry below against their `CLAUDE.md` "Last acknowledged" code for this runbook. If newer, the agent prefixes its first response with `Standards updated:` plus a one-line summary per new entry, then updates the code as part of the session's commit.

- **2026-05-07a** — Initial draft. Defines milestone naming, triage discipline, Discord broadcast layout, and the GitHub events scribe must subscribe to.

## When this applies

Every cog that exposes player-visible issues: tally, flipqueue, tempo, maxcraft, cogworks. Chronoforge meta-tickets (CF-N) and cogworks technical-only meta-tickets do *not* participate — `project_chronoforge_operations` memory establishes that meta-work is internal and not bridged to Discord. The runbook applies to *player-facing* issue trackers only.

## Milestone naming

Per cog, milestones use the **base release version** with no prerelease suffix. One milestone covers all alpha/beta/release tags sharing the base — e.g. `v0.14.0` covers `v0.14.0-alpha1`, `v0.14.0-alpha2`, `v0.14.0-beta1`, and `v0.14.0`. This matches the channel semantics in `feedback_release_channels` (alpha/beta/release are exposure tiers, not maturity tiers — same code, different audiences).

Standard milestones a cog may have open at any time:

- `vX.Y.Z` — the next planned base version. **Required** while any work is in flight.
- `vX.Y.Z+1` (next-after-next) — optional; create only when scope is locked.
- `vX.Y+1.0` — optional; create when actively triaging feature work for the next minor.
- `Backlog` — permanent. Catches every triaged issue that isn't yet committed to a specific version.

`Considering` and `Won't fix` are **labels**, not milestones. Milestones express commitment to ship; labels express other states.

Close a milestone when the matching base-version **release** tag ships (not alpha, not beta). Reopen only if a regression forces re-cutting that version.

## Triage discipline

**Every triaged issue gets a milestone.** No exceptions.

Triaged means: title is accurate, labels applied, scope understood. Until then, the issue stays milestone-less and `won't-fix` candidates get the label and a close. Once triaged, the issue lands in either a specific version (`v0.14.0`) or `Backlog`. Backlog is the parking spot — *not* a dumping ground. Re-evaluate periodically; promote to a version when ready.

Order of operations on a fresh report:

1. Scribe creates the issue from a Discord thread (existing flow).
2. Engineer triages: adjusts title, applies labels, writes scope.
3. Engineer assigns milestone (Backlog or specific version).
4. Scribe posts the per-issue notification back into the originating Discord thread (next section).

Promoting Backlog → version is just a milestone change; the same notification fires.

## Discord broadcast — per-issue notifications

When scribe receives an `issues.milestoned`, `issues.demilestoned`, or milestone-change event for an issue it has a thread mapping for, it posts into the player's thread:

| Transition | Message |
|---|---|
| Milestoned to a specific version (first time) | `🎯 Targeted for **tally v0.14.0**.` |
| Milestoned to Backlog | `📋 Added to the tally backlog.` |
| Re-milestoned (any → version) | `🎯 Now targeted for **tally v0.14.0** (was v0.13.5).` |
| Re-milestoned (any → Backlog) | `📋 Moved to the tally backlog (was v0.14.0).` |
| Demilestoned entirely (cleared) | no message; treat as transient and wait for the next milestone event |

These are threadable status updates that scribe writes directly. They are **not** `## Player update` mirrors and don't require any GitHub-side comment authoring.

The existing post-release per-thread followup (`fanOutThreadFollowups` in scribe `mirror.ts`/`releases.ts`) continues to handle the "✅ shipped in vX.Y.Z" message when the milestone closes. No change there.

## Discord broadcast — pinned roadmap messages

Two surfaces, both maintained by scribe:

1. **Per-cog channel pin** — one pinned message in each cog's primary Discord channel. Lists that cog's open milestones with progress counts.
2. **`#roadmap` aggregate channel** — one channel for the suite. One pinned message per cog, plus a brief suite-wide header. Read-only for non-engineers.

**Format (per-cog):**

```
📍 **Tally roadmap** — last updated 2026-05-07 14:33 UTC

**v0.14.0** — in development · 7 of 12 done · [GitHub →](https://github.com/.../milestone/3)
  • Bag stuck after auction posted
  • Net-worth panel flicker on rest tick
  • Per-item research column wraps at narrow widths
  _(+9 more)_

**Backlog** — 23 issues · [GitHub →](https://github.com/.../milestone/1)

_Each report's status is also posted in its own thread when its milestone changes._
```

Use **issue titles**, not `## Player summary` content. Summaries are written post-fix; titles are good enough pre-fix and avoid empty quotes. Show top 3 titles per milestone inline; rest are counted with `_(+N more)_` and a link to the GitHub milestone view.

**Format (`#roadmap` aggregate):**

Same structure per cog, with milestones not in active development collapsed (only milestone name + count + link). One pinned message per cog rather than one giant message — keeps each under Discord's 4000-char embed cap and lets scribe update one cog at a time.

## Update triggers (scribe webhooks)

Scribe needs three additional GitHub event subscriptions per cog repo:

| Event | Action(s) | What scribe does |
|---|---|---|
| `milestone` | `created`, `edited`, `closed`, `deleted` | Re-render that cog's pinned roadmap message + aggregate entry |
| `issues` | `milestoned`, `demilestoned` (new sub-actions on the existing `issues` event) | Post per-thread notification + re-render that cog's pinned messages |
| `issues` | `opened`, `closed`, `reopened` (already handled) | Re-render (progress counts depend on these) |

**Belt-and-suspenders:** scribe re-renders every pinned roadmap message on a 60-minute timer regardless of webhook activity. Cheap drift recovery if a webhook delivery is missed or scribe was offline.

## Rollout (per cog)

Each cog opts in independently. **Steps 1–2 are the gate**: scribe is not webhook-subscribed for a cog until that cog has done its triage pass. This guarantees players first see a curated roadmap, not a wall of newly-Backlogged tickets dropping into Discord all at once.

For each consumer cog (tally, flipqueue, tempo, maxcraft, cogworks):

1. **Create the initial milestones** via `gh api`:
   ```bash
   gh api repos/gezmodean-wow/<cog>/milestones --method POST -f title="v<next-base>" -f description="Next planned release"
   gh api repos/gezmodean-wow/<cog>/milestones --method POST -f title="Backlog" -f description="Triaged but not yet scheduled"
   ```
2. **Per-cog triage pass** — review every open issue and assign it to either a specific version or `Backlog`. This is human work; agents can prep a draft assignment but the final call is the maintainer's. Don't proceed to step 3 until every open issue has a milestone.
3. **Configure scribe** with the per-cog Discord channel ID for the pinned roadmap message, and (one-time) the aggregate `#roadmap` channel ID.
4. **Subscribe the cog's webhook** to the `milestone` event in addition to its existing subscriptions (`issues`, `issue_comment`, `release`, `create`, `delete`).
5. **Verify:** scribe posts the initial pinned message; nudge a test issue's milestone and confirm both the thread notification and the pin re-render.

Per-cog adoption tickets fan out from the meta-ticket; same pattern as `library-bump-propagation.md`. Use `templates/cog-bump-issue.md` as a starting body, customized for milestone setup.

## Optional: GitHub Project as a coordinator view

A single read-only public Project pulling from all five repos costs nothing to set up and gives a "what's shipping suite-wide this month" view that milestones alone can't produce (milestones are per-repo). Recommended **only** as a coordinator convenience — not the source of truth, not exposed to players (Discord is the player surface). Skip until the milestones-only baseline is operational.

## Pitfalls

- **Milestone closed before the release tag ships.** Closing the milestone is what flips its progress label from "in development" to "shipped." Closing on alpha or beta is wrong — wait for the base-version release tag (no `-alphaN` / `-betaN` suffix).
- **Inconsistent milestone titles across cogs.** Stick to `vX.Y.Z` exactly. No `(in development)`, no quotes, no extra adjectives — the title is parsed as the version string.
- **Backlog as a dumping ground.** Backlog must remain sortable and re-evaluated. Issues that aren't going anywhere get a `won't-fix` label and a close, not a permanent Backlog parking spot.
- **Forgetting to milestone scribe-created issues.** Scribe creates the issue from a Discord report; it does *not* auto-milestone. Triage is human (or agent-driven, but explicit).
- **Bridging mismatch.** Only milestones on bridged repos generate Discord messages. Chronoforge issues (CF-N) deliberately don't bridge — that's by design (`project_chronoforge_operations`). If you find yourself wanting to broadcast a CF-N issue, it probably belongs on a cog tracker instead.
- **Pinned message edited by hand.** Scribe owns the message; manual edits get overwritten on the next re-render. If you need a one-off note, post it as a separate (non-pinned) message in the same channel.

## Canonical example

_Not yet exercised — initial rollout pending CF-9 acceptance._

## Last exercised

_New runbook (2026-05-07)._
