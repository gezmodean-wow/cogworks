# Suite Sync — keeping cogs current with cogworks standards


How standards changes (runbooks, comms conventions, shared/ file pool) flow from cogworks to consumer cogs. Single mechanism: **agent-driven acknowledgments, checked at session start.** Adopted from scribe's existing `PLAYER_FACING_CONVENTIONS.md` model and generalized.

## Standards changelog

- **2026-05-05a** — Initial codification. Generalizes scribe's "Last acknowledged" mechanism to cover all standards sources (runbooks, scribe comms doc, cogworks shared/ file pool).

## The mental model

Each consumer cog's `CLAUDE.md` carries a **Standards acknowledgments** block listing every upstream standards source the cog subscribes to, with the most recent change code the cog has acknowledged.

At session start, an agent fetches each source's current top entry, compares to the local code. If anything is newer:

1. Agent prefixes its first response in chat with `Standards updated:` plus a one-line summary per new entry.
2. Agent applies the change as part of the session's work — behaviorally for convention sources, via the sync script for the file pool.
3. Agent updates the cog's `CLAUDE.md` acknowledgment code as part of the session's commit.

This is **the same mechanism scribe already uses** for `PLAYER_FACING_CONVENTIONS.md`. Generalizing it covers all standards.

## Sources

| Source | Type | Where the changelog lives | Where the acknowledgment lives |
|---|---|---|---|
| Comms conventions | Convention | `cogworks/runbooks/comms-conventions.md` § Standards changelog | Cog `CLAUDE.md` |
| Branch & release flow | Convention | `cogworks/runbooks/branch-and-release-flow.md` § Standards changelog | Cog `CLAUDE.md` |
| Doc conventions | Convention | `cogworks/runbooks/doc-conventions.md` § Standards changelog | Cog `CLAUDE.md` |
| Technical standards | Convention | `cogworks/runbooks/technical-standards.md` § Standards changelog | Cog `CLAUDE.md` |
| Shared file pool | Files | `cogworks/shared/VERSION` | Cog `CLAUDE.md` (entry name `shared/`) |
| Standards-sync (this runbook) | Convention | This file § Standards changelog | Cog `CLAUDE.md` |

Convention sources are agent-applied behaviorally — the agent reads the new entries and changes its behavior accordingly. The file-pool source is automated by `scripts/sync-standards.sh` (vendored from cogworks).

## Cog `CLAUDE.md` block

Every consumer cog's `CLAUDE.md` carries a block like:

```markdown
## Standards acknowledgments

Each session, the agent compares the top entry of each source to the codes
below. If newer, prefix the first response with `Standards updated:` plus a
one-line summary per new entry, then update the code below as part of the
session's commit.

| Source | Last acknowledged |
|---|---|
| [comms conventions](https://github.com/gezmodean-wow/cogworks/blob/main/runbooks/comms-conventions.md) | 2026-05-05a |
| [branch & release flow](https://github.com/gezmodean-wow/cogworks/blob/main/runbooks/branch-and-release-flow.md) | 2026-05-05a |
| [doc conventions](https://github.com/gezmodean-wow/cogworks/blob/main/runbooks/doc-conventions.md) | 2026-05-05a |
| [technical standards](https://github.com/gezmodean-wow/cogworks/blob/main/runbooks/technical-standards.md) | 2026-05-05a |
| [shared/ file pool](https://github.com/gezmodean-wow/cogworks/blob/main/shared/VERSION) | 2026-05-05a — `bash scripts/sync-standards.sh check` |
| [standards-sync (this mechanism)](https://github.com/gezmodean-wow/cogworks/blob/main/runbooks/standards-sync.md) | 2026-05-05a |
```

The `shared/` row references the script because file changes need an apply step — convention rows don't.

## Convention-source flow

When a cog's session begins:

1. Agent reads `CLAUDE.md` § Standards acknowledgments.
2. For each convention source, agent fetches the source's `## Standards changelog` section (just the top few entries).
3. If the source's top code is newer than the cog's:
   - Agent reads the new entries.
   - Agent prefixes the first response with `Standards updated:` and a one-line summary.
   - Agent's behavior in this session reflects the new conventions.
   - Agent updates the cog's `CLAUDE.md` acknowledgment as part of the session's commit (often as a small `chore/ack-standards-<date>` PR if no other work is in flight, or bundled into the session's primary PR).

If multiple sources have updates, the prefix lists all of them.

## File-pool source flow

The `cogworks/shared/` file pool covers in-cog files: PR template, issue templates, the pre-tag-check script, this sync script itself. Adding a new sync target requires updating `cogworks/shared/MANIFEST` (hand-maintained, one path per line).

When a session begins:

1. Agent runs `bash scripts/sync-standards.sh check`.
2. If outdated, agent runs `bash scripts/sync-standards.sh diff` to preview.
3. Agent surfaces the diff to the user; on approval, runs `apply`.
4. Agent commits the file changes plus the `CLAUDE.md` ack update as a `chore/sync-standards-<version>` PR.
5. Standard PR review: CI runs, user merges.

If the user defers (mid-feature, time-pressured, etc.), the agent notes the deferred sync in `chronoforge/.../memory/pending_followups.md` and proceeds with the original task.

## Source maintenance — what to do when changing a standard

For convention sources (any cogworks runbook):

1. Edit the runbook in cogworks via a normal `chore/` or `docs/` PR.
2. Append an entry to the `## Standards changelog` section at the top of the runbook with date code (`YYYY-MM-DDx` — where `x` is a letter to disambiguate same-day edits, scribe convention).
3. Merge to cogworks main.
4. Consumer cogs pick up the change in their next session via the acknowledgment flow.

For the file-pool source:

1. Edit files under `cogworks/shared/` via a normal PR in cogworks.
2. Bump `cogworks/shared/VERSION` to a new code (date-stamped: `2026-05-05a`).
3. If adding a new file, also update `cogworks/shared/MANIFEST`.
4. Merge to cogworks main.
5. Consumer cogs pick up the change via `sync-standards.sh` in their next session.

## Bootstrap procedure (new cog joining)

For a cog that doesn't yet have any acknowledgment block:

1. Open a `chore/bootstrap-standards-acks` PR adding the Standards acknowledgments block to `CLAUDE.md` with codes set to the cogworks current values.
2. Run `bash scripts/sync-standards.sh apply` to seed the file-pool files into the cog (creates `.github/pull_request_template.md`, etc.).
3. Commit the synced files and the `CLAUDE.md` block together.
4. Merge.

Subsequent sessions are normal — the agent picks up changes via the acknowledgment check.

## Override mechanism

Per-cog opt-out for the file-pool source lives in `.cogworks-sync-skip` at the consumer repo root. One path or glob per line, comments with `#`:

```
# Local overrides that resist cogworks sync
.github/ISSUE_TEMPLATE/bug.md
scripts/pre-tag-check.sh
```

Used sparingly. The point of sync is convergence; overrides are an escape valve.

For convention sources there's no equivalent override — if a cog disagrees with a convention, the right move is to raise it in cogworks and either change the convention or document the per-cog exception there.

## Failure modes and recovery

- **Agent forgets to check at session start.** Mitigation: each cog's `CLAUDE.md` should call out the check in its agent-onboarding section, near the top. Agents read CLAUDE.md as standard practice; the check becomes part of session boot.
- **Cogworks unreachable.** Acknowledgment check fails gracefully; agent proceeds with original task and notes the failure. Next session retries.
- **Sync script downloads a broken file.** `apply` is reviewed in a chore PR before merge; cog CI runs on the PR; broken file fails CI and PR doesn't merge. Fix lands in cogworks; next sync supersedes.
- **Two sources update simultaneously and conflict.** Agent surfaces both, asks user how to sequence. Defer one if needed.
- **Acknowledgment code drifts (out-of-band edits to the changelog).** Re-acknowledge by reading the latest entries and updating the code. The code is just a marker; truth lives in the source.

## Relationship to other runbooks

- **`branch-and-release-flow.md`** — when sync produces a `chore/sync-standards-<version>` PR, it flows through the standard branch/PR/release cycle.
- **`doc-conventions.md`** — defines RELEASES.md / CHANGELOG.md formats; not sync-managed.
- **`comms-conventions.md`** — comms standards consumed by scribe; convention-source for the acknowledgment mechanism.
- **`technical-standards.md`** — engineering conventions; convention-source.
- **`scribe/docs/PLAYER_FACING_CONVENTIONS.md`** — historical home of the comms conventions; superseded by `comms-conventions.md` on adoption. Scribe's parser code stays in scribe.

## Last exercised

_New runbook; not yet exercised._
