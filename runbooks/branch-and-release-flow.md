# Branch and release flow


This runbook is the canonical reference for how a single cog branches, opens PRs, tags, and releases. It applies to flipqueue, tally, tempo, maxcraft, and cogworks itself. Scribe (the Discord ↔ GitHub bridge) is a different shape and out of scope.

The two audiences this serves:
1. **Agents implementing changes**, who need clear stop points, scriptable gates, and explicit "ask the user" moments.
2. **The user reviewing**, who needs a one-screen diff, a written test plan, and a checklist that says what mechanical gates passed.

## Standards changelog

Sessions check the top entry below against their `CLAUDE.md` "Last acknowledged" code for this runbook. If newer, prefix the first response with `Standards updated:` plus a one-line summary per new entry, then update the cog's acknowledged code as part of the session's commit.

- **2026-05-06a** — Branch naming convention now requires issue encoding when work is issue-linked. Format: `<type>/<COG-N>-<slug>` (e.g. `fix/FQ-147-bag-taint`). Chore work without an issue keeps `<type>/<slug>`. Scribe parses branch names via `^[a-z]+\/([A-Z]+-\d+)-` to track in-progress state on linked issue threads.
- **2026-05-05a** — Initial codification. GitHub Flow + tagged releases; PR discipline (always open even solo, draft while WIP, squash-merge); release flow (soak window, pre-tag check, hotfix branches off the tag); channel semantics (alpha/beta/release label exposure not maturity, promotion by re-tagging the same commit, `-alpha2` only on player feedback); F1–F8 pre-tag checklist (mechanical via `scripts/pre-tag-check.sh`, F8 in-game smoke test is human-only); severity → channel mapping.

## Branch model — GitHub Flow + tagged releases

- `main` (or `master` for flipqueue) is **always shippable**, but never auto-shipped. Tags are the release artifact; the `human_gate_before_release` rule still gates upload to CurseForge / Wago.
- Work happens on **short-lived branches**, named by intent (see naming rules below).
- **No `develop` branch.** Single trunk plus topic branches.
- **No long-running release branches.** A release is a tag at a commit on main, not a branch.

## Branch naming

**Issue-linked branches** (the common case — any feature, bug fix, or chore tied to a tracked ticket):

```
<type>/<COG-N>-<slug>
```

Where:
- `<type>` is one of `feat | fix | chore | docs`
- `<COG-N>` is the cog-internal issue ID — `FQ-147` (flipqueue), `TLY-49` (tally), `TMP-12` (tempo), `MXC-3` (maxcraft), `COG-30` (cogworks). The number matches the GitHub issue number 1:1.
- `<slug>` is a short kebab-case description

Examples:
- `fix/FQ-147-bag-taint`
- `feat/TLY-49-blob-storage`
- `chore/COG-30-static-popup-rebind`
- `docs/TMP-12-readme-cleanup`

**Issue-less branches** (chore work with no ticket — CI tweaks, tooling, suite-wide bootstraps):

```
<type>/<slug>
```

Examples: `chore/adopt-suite-standards`, `chore/bootstrap-suite-standards`, `chore/pin-cogworks-workflow-v0.13.2`.

**Why the issue-encoding matters:** scribe parses branch names to set `in_progress` status on the linked issue's Discord thread when a branch with `<COG-N>` is created, and reverts only on issue close (not on branch delete — branches get rebased / squashed away constantly during work). The regex scribe uses: `^[a-z]+\/([A-Z]+-\d+)-`. Branches without that prefix are treated as not-issue-linked and skipped.

**Type prefixes:**
- `feat/` — new functionality
- `fix/` — bug fix
- `chore/` — refactor, dep / pin bump, CI, packaging
- `docs/` — runbook / readme only

## PR discipline

Even solo, every non-trivial change goes through a PR. The PR is the only place the full diff is reviewable as one unit, and it's the natural anchor for `Closes <ID>`.

- **Open as draft while WIP.** Mark ready when the diff is something you'd hand to a reviewer.
- **Squash-merge by default.** Main's history stays one commit per logical change; the branch keeps the messy intermediate commits as context.
- **Self-review before mark-ready.** PR template's checklist (`templates/pull-request.md` in this draft, vendored as `.github/pull_request_template.md` once adopted) covers issue link, manual exercise, CI green, no leftover debug, RELEASES.md / CHANGELOG.md updated.
- **One logical change per PR.** Don't bundle a Cogworks-1.0 bump with feature work. Don't bundle multiple unrelated bugfixes. Bundling makes hotfix reverts harder and review slower.

## Release flow

1. Merge to main lands changes; main is shippable but unshipped.
2. **Soak window.** No fixed days — but don't tag and walk away inside the same hour you merged. Exercise the change on the local install first.
3. **Run the pre-tag check.** `scripts/pre-tag-check.sh <tag>` (vendored from cogworks/shared/ via Suite Sync). Reports F1–F7 mechanical gates plus the F8 manual reminder.
4. Tag from main (`git tag vX.Y.Z[-channelN] && git push --tags`). The cog's `release.yml` runs verify-package, then BigWigsMods/packager uploads to CurseForge + Wago.
5. **Hotfix path:** branch from the *release tag*, fix, PR back into main, tag `vX.Y.Z+1` from main. The tag itself is the immutable point — no separate release branch.

## Channel semantics — alpha / beta / release

All three channels ship **functionally-complete** code. The label is about *exposure*, not *maturity*.

- **Alpha** — opt-in player exposure of a complete change. Tag once. `-alpha2` only exists when player feedback (or a real bug surfaced post-tag) forced new code, not as an iteration mechanism.
- **Beta** — optional release candidate. Same code you'd be willing to call stable, exposed earlier to the beta cohort. Skipping beta is fine; using it twice for the same `vX.Y.Z` isn't.
- **Release** — default channel. Tagged when alpha exposure (if any) cleared and soak passed.

**Promotion is by re-tagging the same commit.** `v0.14.0-alpha1` at commit C → `v0.14.0` at commit C, no code change. A version increment means new code; a channel change doesn't.

**"Release early and often" applies to versions, not iterations within a version.** Prefer many small `v0.N.0` over churning alphas of one version. The signal "alpha-N+1 was published" should mean "someone reported something" — not "the developer is iterating in the open."

## Pre-tag checklist (F1–F8)

The mechanical checks (F1–F7) live in `scripts/pre-tag-check.sh`. F8 is a human-only gate — agents call it out and stop.

| # | Check | How |
|---|---|---|
| F1 | Working tree clean on main | `git status` empty, branch is main/master |
| F2 | CI green on the tag's commit | `gh run list --branch main --limit 1` shows success |
| F3 | `.pkgmeta` Cogworks pin matches what was tested | Note the pin; agent declares whether the pin matches the version exercised in F8 |
| F4 | RELEASES.md has a section for the new tag | Grep for tag string |
| F5 | CHANGELOG.md has an entry for the new tag | Grep for tag string |
| F6 | Tag name uses literal "alpha" / "beta" (not "-aN" / "-bN") | Regex check |
| F7 | Closed-issue refs since previous tag are referenced in CHANGELOG | Diff `git log <prev>..HEAD` against CHANGELOG.md |
| F8 | **Human-only:** local in-game smoke test was performed against the tag's commit | Agent asks the user; never fabricates |

Agent flow when proposing a tag: run the script, paste the output to chat, then explicitly request F8 confirmation from the user before pushing the tag.

## Severity → channel mapping (for hotfixes)

- **Critical** (blocks login, corrupts saved variables, Lua error on every UI open) — patch release direct to stable, soak window can be one play session.
- **High** (functional regression with workaround) — next planned alpha is fine; not worth a special release.
- **Medium** (annoyance, polish) — next minor's alpha or release.
- **Low** (cosmetic) — bundle into the next minor.

## Cross-cog considerations

- **Cogworks-1.0 library bumps** in `.pkgmeta` follow `chronoforge/runbooks/library-bump-propagation.md`. Each consumer cog's bump is a `chore/bump-cogworks-vX.Y.Z` PR through the flow above.
- **Cogworks reusable-workflow refs** in `release.yml` must pin to a tag (not `@main`). Same `chore/` PR shape. See the supply-chain rule in `doc-conventions.md` (rule B2 in the original proposal). Bump library + workflow ref to the same tag in one PR.
- **Standards changes** (PR template, issue templates, pre-tag script) flow automatically via Suite Sync. See `standards-sync.md`. The user does not file per-cog tickets for these — the sync workflow files them.

## Branch protection (recommended)

Optional but cheap: enable branch protection on each cog's main with these rules:
- Require PRs for all merges (no direct push).
- Require `verify-package` status check green.
- Allow squash-merge only.

Solo-dev caveat: don't require *reviewers* — that just blocks you from merging your own PRs.

## Last exercised

_New runbook; not yet exercised. Append a `## Last exercised: YYYY-MM-DD — <issue ID>` line each time this flow drives a real release._
