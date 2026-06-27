# Runbook: cross-repo coordination

> **Status: adopted (2026-06-27).** Canonical home — migrated from `chronoforge/runbooks/` to `cogworks/runbooks/` per cogworks#42 (CF-10). Cogworks hosts the canonical runbook set; the chronoforge draft is removed under CF-10.

How work that crosses repo boundaries flows across the suite without the user becoming the messenger. Two pieces: a **label** that marks cross-repo tickets so they're discoverable, and a **session-start pre-flight** that surfaces inbound work to the resident agent before it picks up its first task.

The runbook also codifies the **access model** — who can survey what. Default is repo-scope; cogworks and chronoforge are the privileged exceptions.

## Standards changelog

Cog and scribe sessions check the top entry below against their `CLAUDE.md` "Last acknowledged" code for this runbook. If newer, the agent prefixes its first response with `Standards updated:` plus a one-line summary per new entry, then updates the code as part of the session's commit.

- **2026-05-07a** — Initial draft. Defines `cross-repo-inbound` label, session-start pre-flight, access model, cogworks survey role, chronoforge cross-cog diagnosis role.

## Access model

Six repos in the suite (`cogworks`, `tally`, `flipqueue`, `tempo`, `maxcraft`, `scribe`), plus `chronoforge` for coordination.

| Repo session | Default cross-repo reach |
|---|---|
| **chronoforge** | Read on all 6 sibling repos. Files cross-repo issues as part of coordinator role. Does **not** edit sibling repo files (per `feedback_coordinator_owns_spec_not_impl`). |
| **cogworks** | Read on the 4 consumer cogs (tally, flipqueue, tempo, maxcraft) for library-generalization survey. Files cross-repo issues to consumers and to chronoforge. Does not read scribe (not a library consumer). |
| **tally / flipqueue / tempo / maxcraft** | Repo-scoped by default. Reads sibling repos only with explicit per-project authorization (e.g. if tally ever consumes flipqueue's auction data as a feature). May read cogworks documentation since they vendor it. Files cross-repo issues to cogworks (library asks) and chronoforge (cross-cog bugs / coordinator surfacing). |
| **scribe** | Repo-scoped by default. Files cross-repo issues to chronoforge (coordinator surfacing). |

**Cross-cog bugs route through chronoforge.** When a player report or symptom looks like it spans more than one cog, the cog session that received it should *not* try to diagnose across siblings. Surface the report to the user; the user brings it to chronoforge, which has the cross-repo reach to investigate and fans out per-cog tickets.

## The `cross-repo-inbound` label

Every cross-repo ticket — one filed by chronoforge or cogworks (or any repo) **into another repo** — gets the `cross-repo-inbound` label at filing time. This makes inbound work discoverable to the receiving repo's session.

Companion labels (optional, additive):

| Label | Meaning |
|---|---|
| `cross-repo-inbound` | **Required.** Filed from outside this repo. |
| `from-chronoforge` | Filed by chronoforge (coordinator). |
| `from-cogworks` | Filed by cogworks (library generalization or consumer-side bug spotted from library work). |
| `from-<consumer-cog>` | Filed by a consumer cog (e.g. `from-tally`). Used for cog → cogworks library asks. |
| `library-generalization-candidate` | Cogworks-internal label for outbound surveys. Self-applied; not cross-repo. |

The receiving repo creates these labels on first use; the runbook does not pre-provision them (cheap, runs the first time `gh issue create --label cross-repo-inbound` runs against the repo).

## Session-start pre-flight

Each cog and scribe session runs an **inbound pre-flight** at session start, after the standards-acknowledgments check.

```bash
gh issue list --repo gezmodean-wow/<this-repo> --label cross-repo-inbound --state open
```

If the result is non-empty, surface to the user before proceeding to whatever task they opened the session for:

> **Inbound from outside this repo:** 3 open tickets labeled `cross-repo-inbound`. List below; pick one to start with, or proceed with your own task.
> - #N: ...
> - #N: ...

If empty, proceed silently.

This is a **pre-flight**, not a gate. The user can ignore inbound and tell the session to do something else; the inbound stays in the queue for next time.

## Filing cross-repo tickets

When a session needs to file a ticket on another repo:

```bash
gh issue create \
  --repo gezmodean-wow/<target> \
  --title "<title>" \
  --label cross-repo-inbound \
  --label from-<source> \
  --body "$(cat <<'EOF'
## Why

<context — why this ticket is filed *from* the source repo, what symptom or need triggered it>

## Acceptance for the receiving repo

- [ ] <specific outcome>
- [ ] <specific outcome>

## Source context

Filed from: gezmodean-wow/<source> (session in C:/src/<source>)
Related: <issue link if any>

## Handoff to <target> session

When picking this up in C:/src/<target>:

1. <reading list>
2. <design step — comment back before executing>
3. <execution>
EOF
)"
```

The `## Handoff to <target> session` block is the contract. Coordinator owns the *what*, target session owns the *how*.

## Surveying (cogworks-only, by default)

Cogworks has read access on the 4 consumer cogs to spot generalization opportunities. The pattern:

1. **Survey.** Read consumer code for repeated patterns. `Read`, `Glob`, `Grep` against `C:/src/{tally,flipqueue,tempo,maxcraft}/`.
2. **File the cogworks-side ticket.** Title: "Generalize <X> into Cogworks-1.0". Label: `library-generalization-candidate`. Include consumer code samples with file:line refs that motivated the survey.
3. **Triage.** Assign milestone (per `roadmap-and-version-broadcast.md`).
4. **Implement.** Cogworks code work happens on the cogworks side; existing `library-bump-propagation.md` runbook covers the downstream fan-out.
5. **File per-consumer adoption tickets** when the library lands. Same label conventions as any cross-repo work.

The 1→2 step is what's privileged. Other cogs **don't** survey siblings; that's not their job.

## Cross-cog bug diagnosis (chronoforge-only)

When a bug report comes into a cog and the symptom suggests it spans cogs (e.g. taint that originates from cogworks but manifests in flipqueue), the cog session does **not** survey siblings. Instead:

1. Cog session captures the report in its own tracker (existing flow via scribe).
2. If the symptom looks cross-cog, the cog session **flags it to the user** with a recommendation: "this looks cross-cog; bring to chronoforge for diagnosis."
3. User opens a chronoforge session. The user brings the report; chronoforge files a `CF-N` (or refers to an existing one).
4. Chronoforge surveys across affected repos using its cross-repo read.
5. Chronoforge diagnoses, then files per-cog implementation tickets back to the affected cogs with the diagnosis and required fix per cog. Each ticket gets `cross-repo-inbound` + `from-chronoforge` labels.
6. Each cog session picks up its inbound ticket via the pre-flight and implements.

This keeps cross-cog reasoning concentrated in chronoforge — which has the reach and the mandate — instead of every cog session trying to do detective work it isn't scoped for.

## Adoption — what each repo's CLAUDE.md needs

Per the CF-8 audit, each cog and scribe `CLAUDE.md` needs three changes (or four for cogworks/tempo/maxcraft, which also need the modern standards-ack table). The CF-8 sweep tickets carry the per-file specifics; this runbook supplies the canonical wording.

### `## Coordinator (chronoforge)` section (all 6 files)

```markdown
## Coordinator (chronoforge)

Suite-wide coordination — runbook drafting, audits, multi-cog initiatives, cross-cog bug diagnosis — happens in `gezmodean-wow/chronoforge` (issue prefix `CF-N`). Cross-repo work routed *to* this repo from chronoforge or cogworks lands as a GitHub issue with the `cross-repo-inbound` label.

**Session-start pre-flight:** after the standards-acknowledgments check, run:

```bash
gh issue list --label cross-repo-inbound --state open --repo gezmodean-wow/<this-repo>
```

If non-empty, surface inbound tickets to the user before proceeding to their task. If empty, proceed silently.

Don't read or modify chronoforge from here — it's the coordinator's repo, not part of this repo's scope. Scribe note: scribe doesn't bridge chronoforge issues to Discord (per `project_chronoforge_operations`); CF-N work is engineering-internal.
```

### `## Cross-cog work` section (consumer cogs)

```markdown
## Cross-cog work

This cog's session is **repo-scoped**. Don't survey sibling cogs from here.

When work surfaces a need outside this cog:

- **Cogworks library gap** → file a GitHub issue on `gezmodean-wow/cogworks` with labels `cross-repo-inbound` and `from-<this-cog>`. Continue with whatever stub work is possible; cogworks's session picks up the ticket via its pre-flight.
- **Cross-cog bug or behavior** → don't try to diagnose from here. Surface to the user; the diagnosis belongs in chronoforge.
- **Inbound work** → the session-start pre-flight surfaces these via the `cross-repo-inbound` label.

Per the access model, only chronoforge (coordinator) and cogworks (library) have default cross-repo read. Per-project explicit authorization is the exception.
```

### `## Cross-cog work` section (cogworks variant)

```markdown
## Cross-cog work

Cogworks is the **shared library**, so cross-cog work is part of the job:

- **Inbound asks from consumers** (`cross-repo-inbound`, `from-<cog>`) → triage as a real signal that a library capability is missing. Promote to a milestone if the work is committed.
- **Outbound generalizations** → cogworks has read access on all consumer cogs. Survey for repeated patterns; file `library-generalization-candidate` issues on cogworks with consumer code samples that motivated them. When library work ships, fan out per-consumer adoption tickets per `library-bump-propagation.md`.
- **Outbound asks to consumers** → file a `cross-repo-inbound` + `from-cogworks` issue on the relevant consumer repo.

Per the access model, this cog is one of the two with privileged cross-repo reach (the other is chronoforge). Use it.
```

## Pitfalls

- **Forgetting the label at filing time.** A ticket without `cross-repo-inbound` won't appear in the receiving session's pre-flight. The receiving session won't know it exists until prompted. If you spot one, just add the label after the fact.
- **Cog session doing cross-cog diagnosis anyway.** Tempting when the symptom is right there. Resist — it concentrates the cross-cog reasoning where the access and the mandate actually are. The cog's job is "fix my repo when chronoforge says what to fix."
- **Bypassing the pre-flight.** If the user prompts the session immediately ("do issue #X"), the session may skip the pre-flight. Fine — the inbound stays queued for next session start.
- **Pre-flight on chronoforge itself.** Chronoforge does *not* receive `cross-repo-inbound` tickets (it's the coordinator, not a downstream). Its pre-flight is a no-op. Don't add it to chronoforge's CLAUDE.md.
- **Label sprawl.** Resist adding more `from-X` variants beyond the canonical set. If a repo emerges that needs a new source label, add it here and adopt across all CLAUDE.mds in one sweep.

## Canonical example

_Not yet exercised — initial rollout pending CF-10 acceptance and the per-cog CLAUDE.md sweep._

## Last exercised

_New runbook (2026-05-07)._
