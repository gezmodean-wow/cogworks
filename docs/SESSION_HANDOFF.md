# Session handoff — 2026-05-11 (evening close)

Snapshot for the next agent picking up Cogworks work. **Generator was killed mid-run; PR #54 is still in flight.** Read this first.

## Resume sequence (do these in order)

1. **Verify state matches this doc.**
   ```powershell
   git status                      # expect: clean on main, ahead 0 / behind 0
   git log --oneline -4            # expect 7f5fc72 (COG-56 merge) at the top
   gh pr list --repo gezmodean-wow/cogworks --state open
   ```
   You should see one open PR: **#54 (draft) feat(COG-28): ItemBase loader scaffold** based on `feat/COG-28-item-base-generator`.

2. **Confirm BNET creds still inherited** (only matters if you're picking the generator back up):
   ```powershell
   echo "id: $([Environment]::GetEnvironmentVariable('BNET_CLIENT_ID','User') -ne $null)"
   echo "sec: $([Environment]::GetEnvironmentVariable('BNET_CLIENT_SECRET','User') -ne $null)"
   ```
   Both should be `True`. They're set as User-scope env vars.

3. **Per-user-directive priority is FlipQueue unblockers, not the generator.** User said 2026-05-11: *"Get debug working first, then get flipqueue unblocked, check your tasks to see if anything else urgent is there, then go back to making the item base work a little more efficient."* Debug is done (PR #57 merged). Next is shipping the three FQ-unblocker primitives (#36 / #38 / #40 — all required; dealer's choice on order). Generator finalization sits in parallel and isn't on the critical path until those three ship.

4. **(If picking the generator back up) Resume from scan position 71001.** Last alive line in the kill log was `... scanned 71000 ids, kept 19701`. Resumable via:
   ```powershell
   git switch feat/COG-28-item-base-generator
   python tools/generate-item-base.py --locale enUS --rps 80 --workers 8 --start-id 71001
   ```
   **CAVEAT:** the script's `--start-id` does not merge with a prior partial-run output file — it generates a Lua file for the range you give it. To get a *complete* data file you'd need to either (a) run the full range in one shot, or (b) build a small merge step. Easiest path: re-run the full range 1→250000 when you actually want the data file. ~2h with 8 workers at the measured 34 req/sec.

5. **Once the generator finishes**, commit + flip PR #54 ready:
   ```bash
   git add Cogworks-1.0/Data/ItemBase-Generated-enUS.lua
   git commit -m "feat(COG-28): bundle generated enUS ItemBase data file"
   git push
   gh pr ready 54 --repo gezmodean-wow/cogworks
   ```

## Status flag

- **PR #57 (COG-56 debug fix) — MERGED** as squash commit `7f5fc72` on `main`. Standalone Cogworks's `CreateDebugConsole` no longer crashes on first open. lib MINOR is now `20`. User said they'd re-sync their AddOns/Cogworks/ dir themselves to pick up the fix in-game.
- **PR #54 (COG-28 ItemBase) — DRAFT, rebased onto post-#57 main.** 4 commits: scaffold + version-from-namespace + locale-fix + ThreadPoolExecutor parallel. Bumps lib MINOR `20 → 21`. Awaiting the real `ItemBase-Generated-enUS.lua` data file (placeholder currently in tree).
- **Generator (PID was 50904) — KILLED on user request at session close.** Last progress line: `scanned 71000 ids, kept 19701`. Stderr log was at `$env:TEMP\itembase-gen.stderr.log` (will be there until temp cleanup runs). PID file at `$env:TEMP\itembase-gen.pid`. No process is running now.
- **Issue #58 filed** (refresh-itembase cron + version-probe auto-regen). **User directive: do not implement until after #36 / #38 / #40 ship.**
- **Branch protection rule on `main` was patched this session.** Required check is now `verify` (was `verify / verify`, which never matched the actual CheckRun name — that's why PR #57 initially refused to merge). Future PR merges should work without the `--admin` flag.

## Since the last handoff snapshot (2026-05-03 in tree; 2026-05-07 effectively, via PR #48)

| Tag / event | Date | Note |
|---|---|---|
| PR #48 merged | 2026-05-07 | shared/ bootstrap fixes + `.gitattributes` |
| PR #54 opened (draft) | 2026-05-10 | COG-28 ItemBase loader scaffold |
| Issue #55 filed | 2026-05-10 | `cw-inner.tga` packaging miss |
| Issue #56 filed | 2026-05-11 | Debug console crash root-caused |
| PR #57 opened | 2026-05-11 | COG-56 fix: TabPanel `lazy` opt + late SetActiveTab |
| PR #57 merged | 2026-05-12 (UTC) | Squash `7f5fc72`. lib MINOR `19 → 20`. |
| Issue #58 filed | 2026-05-11 | Cron auto-regen follow-up to PR #54 |
| Branch protection patched | 2026-05-11 | `verify / verify` → `verify` on main protection |
| PR #54 rebased | 2026-05-11 | Onto post-#57 main; lib MINOR bump now `20 → 21` |

## Today's session — what was learned the hard way

These are notes worth keeping; they aren't in code or git log.

- **Local `main` divergence from a prior session was stale.** Reset hard to origin/main after confirming the two local-only commits (an old merge + a 2026-05-05 SESSION_HANDOFF) were superseded by PR #48. No work lost.
- **`enUS` is NOT a valid Blizzard Game Data API locale.** WoW client uses `enUS` (no underscore); the API needs `en_US`. Sending the WoW form silently switches Blizzard to returning `name` as a `{en_US: "...", de_DE: ...}` dict, which crashes the generator's `.lower()` normalization. Script now translates via `api_locale()` at the URL-build boundary.
- **The generator was single-threaded sync HTTP.** Per-request RTT to Blizzard is ~180ms, so one worker tops out at ~5.5 req/sec regardless of `--rps`. Full 250k-id run was projected at ~12h. Refactored to `concurrent.futures.ThreadPoolExecutor` with thread-safe slot reservation in `_throttle`. Measured ~34 req/sec at 8 workers (smoke test: 1000 ids in 29s). Projects to ~2h for full 250k.
- **Generator stderr is block-buffered when redirected.** When the script is launched via `Start-Process -RedirectStandardError`, progress lines accumulate in the OS buffer and flush in batches. Don't be misled by sudden jumps in the log — actual cadence is the `--rps`-cap-and-RTT product.
- **`Start-Process` is the right launcher for long detached jobs on Windows.** The `Bash` / `PowerShell` tool's `run_in_background` mode is capped at a 10-min timeout, which would kill any 2h+ job. `Start-Process` spawns a process that survives independent of the tool lifecycle. Save the PID to a sidecar file; poll via `Get-Process -Id`.
- **`git switch` fails dirty, but `git reset --hard` does not.** During the main-reset attempt mid-session, the chained `git switch main; git reset --hard origin/main` switched silently failed (working tree was dirty with the in-progress SESSION_HANDOFF rewrite from the prior session) but the reset ran on the *current* branch instead, blowing away the COG-28 scaffold commit tip locally (origin was untouched, so `git pull --ff-only` recovered cleanly). Lesson for next time: chain reset operations with `if ($LASTEXITCODE -eq 0)` guards so a failed switch can't quietly redirect to the wrong branch.

## Open issues snapshot

20 open. Recent + priority:

- **#36 Stepper, #38 Drawer animated, #40 ShowLoading — NEXT SESSION'S WORK.** All required by FQ #143 (Phase B + C). User says all three need to ship; dealer's choice on order. Severity: #36 is high, #38/#40 are medium. Ship as separate PRs so they can be tested/merged individually.
- **#37 sidebar scroll, #41, #43, #44, #45, #46** — also FQ #143 dependencies but lower-priority within that audit. Pick up after the headline three.
- **#42, #47** — from-chronoforge cross-repo asks (CLAUDE.md sweep + roadmap broadcast standard). Not blocking anything; pick up during a CLAUDE.md/governance sweep session.
- **#49** minimap position regression — awaiting reporter SV file. No code change indicated until repro detail lands.
- **#55** `cw-inner.tga` packaging miss. Cleanup ticket; release-blocker only when next packaging fix release goes out.
- **#58** ItemBase cron auto-regen — filed this session as a follow-up to PR #54. Do NOT pick up until #36/#38/#40 ship.
- **#28 ItemBase** — covered by PR #54.
- **#1, #2, #12, #23, #31** older backlog; user previously held off these pending FQ #143 close.

## Open PRs

- **#54 (draft)** feat(COG-28): ItemBase loader scaffold. Branch: `feat/COG-28-item-base-generator`. 4 commits ahead of main. Lib MINOR `20 → 21`. Waiting on the real generated data file before going ready-for-review.

## Player-update conventions

Last acknowledged SCRIBE changelog code: `2026-04-30f` (verified live during this session via WebFetch; no newer entries). No CLAUDE.md update required.

## Notes / gotchas

- **Cogworks `CHANGELOG.md` on `main`** currently has no `## Unreleased` section (a hook stripped it after the #57 squash merge — confirmed intentional by system reminder). The COG-28 PR's CHANGELOG will re-add it on merge. If the same hook strips it again, that's fine; the convention seems to be that Unreleased lives only on feature branches between releases.
- **MINOR sequencing during PR merge.** PR #54 currently bumps `20 → 21`. If any other fix lands on main before #54 merges, rebase + bump again. The pattern is now well-rehearsed.
- **Generator `--rps` is a *ceiling*, not a floor.** Under contention with 8 workers, actual rate is closer to 34 req/sec (bounded by per-request RTT × 8). If you need to go faster, bump `--workers` rather than `--rps`. Blizzard's free-tier limits are 100/sec instantaneous + 36k/hr; we're well under at 34/sec until the hourly soft cap kicks in around 17 min.
- **In-game testing burden.** All three of #36/#38/#40 need user-side in-game smoke testing. Plan one PR at a time so the user can test/merge between, rather than batching.
- **Standalone packager + release** has not been triggered this session. PR #57's fix is on main but no release tag has been cut. Per the human-gate-before-release memory, never auto-tag; user must explicitly green-light.

## Task list at handoff

(Persistent task ids from the harness's TaskList — these survive across sessions only inside the harness; this dump is for human reference.)

```
#1 [completed] Reconcile main vs origin/main
#2 [completed] Split stash → COG-28 PR #54
#3 [completed] Split stash → COG-56 fix branch
#4 [in_progress] Run ItemBase generator at --rps 80   (process killed; resume requires re-deciding strategy)
#5 [pending]    Commit ItemBase data + mark PR #54 ready
#6 [pending]    Ship #36 CreateStepper primitive       ← NEXT
#7 [pending]    Ship #38 Drawer animated edge-reveal   ← NEXT
#8 [pending]    Ship #40 ShowLoading primitive          ← NEXT
```

## Project state at handoff

- Local branch: `main`, up to date with `origin/main`. Working tree clean (before this SESSION_HANDOFF.md write).
- Last commit on main: `7f5fc72 fix(COG-56): CreateDebugConsole crash from eager tab activation (#57)`.
- Last release: `v0.13.2` (2026-05-05). No release tag has been cut for the COG-56 fix; that's deferred until the FQ-unblocker triplet ships, at which point cutting a single `v0.14.0` is the likely plan.
- Closed this session: #56 (via PR #57).
- Filed this session: #58.
- Open + active: #54 (draft).
