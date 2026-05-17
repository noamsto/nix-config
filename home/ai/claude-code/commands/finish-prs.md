---
description: "Fan out across my open PRs in the current repo: one teammate per PR → babysit each to CI-green + comments-clean"
argument-hint: "[--all] [--repo OWNER/REPO] [--pr N,M,...] [--limit N] [--concurrency N] [--dry-run]"
---

# Finish PRs: Multi-PR Shepherd Fan-Out

You are the **team lead**. You select a batch of the user's already-open PRs, spawn one teammate per PR, and each teammate babysits its PR through CI failures and reviewer comments until everything is clean. You coordinate; you do not implement.

This is the third member of the autopilot family:

- `/autopilot` — single Linear ticket → PR → green (creates the PR)
- `/project-autopilot` — multi-ticket fan-out (creates PRs)
- `/finish-prs` — multi-PR fan-out for **already-open** PRs (shepherds existing PRs)

**Argument:** `$ARGUMENTS`

Parse the args:

- **Default scope:** the current repo (auto-detected from `gh repo view --json nameWithOwner -q .nameWithOwner` in the invocation directory). If that fails (not in a repo), abort with a friendly error and suggest `--all` or `--repo`.
- `--all` — operate across all repos containing PRs by me (cross-repo mode)
- `--repo OWNER/REPO` — restrict to one specific repo (overrides current-repo detection; mutually exclusive with `--all`)
- `--pr N,M,...` — restrict to specific PR numbers (requires a single repo — current, `--repo`, or first match if `--all`)
- `--limit N` — max PRs to dispatch this run (default: 10)
- `--concurrency N` — max teammates simultaneously (default: 3)
- `--dry-run` — show the batch and exit without spawning anything

---

## Step 1: PR Discovery

Resolve scope first:

- If `--pr` given: fetch each PR directly with `gh pr view <N> --repo <SCOPED-REPO> --json …`
- Else if `--all`: list across all repos
  ```bash
  gh search prs --author @me --state open --json number,title,repository,url,isDraft,headRefName --limit 50
  ```
- Else (default): list PRs in the current/`--repo` repo only
  ```bash
  gh pr list --author @me --state open --repo <OWNER/REPO> --json number,title,url,isDraft,headRefName --limit 50
  ```

Drop drafts unless explicitly listed in `--pr`. Cap to `--limit`.

For each PR, also fetch its current health:

```bash
gh pr checks <N> --repo <OWNER/REPO>
gh api repos/<OWNER/REPO>/pulls/<N>/comments
gh api repos/<OWNER/REPO>/issues/<N>/comments
gh api repos/<OWNER/REPO>/pulls/<N>/reviews
```

Classify each PR:

- **Green** — all checks passing (except Apps Sanity Gate), no unaddressed comments → skip, no work needed
- **Red** — failing check OR unaddressed reviewer comment → dispatch a teammate
- **Stuck** — same failing state >24h with no new commits → flag in the report; still dispatch unless the user opted out

"Unaddressed comment" = posted after the latest commit by me on the PR branch.

## Step 2: Pre-Flight & Confirmation

Present the batch:

```
## Finish-PRs Plan

**Concurrency:** N teammates at once
**PRs to shepherd:** M (skipped K already-green)

| # | Repo | PR | Title | Failing checks | Unaddressed comments | Last push |
|---|------|----|----|------|------|------|
| 1 | factify-inc/mono | #1234 | … | 2 | 1 bot, 1 human | 4h ago |
| 2 | factify-inc/mono | #1241 | … | 0 | 2 human | 2d ago |
…

Proceed? Any PRs to drop?
```

**Always pause here.** If `--dry-run`, stop after the table.

## Step 3: Team Setup

**Pre-flight:** confirm `teammateMode` in `~/.claude/settings.json` is `"in-process"` while [anthropics/claude-code#58724](https://github.com/anthropics/claude-code/issues/58724) is open — `"tmux"` / `"auto"` currently die on spawn with `Error: Input must be provided … --print` because claude-code ≤ 2.1.140 builds the teammate launch line without a prompt arg (verified minimal repro: `.claude-wrapped --agent-id X --agent-name Y --team-name Z --agent-type general-purpose`). When that issue is closed, flip back to `"tmux"` for per-PR pane theater.

Create the team with `TeamCreate`:

- `team_name`: `finish-prs-<YYYYMMDD-HHMM>`
- `description`: "Shepherding PRs: <repo#N, repo#M, ...>"
- `agent_type`: `lead`

Create one task per PR with `TaskCreate`:

- `subject`: `<repo>#<N>: <PR title>`
- `description`: PR URL + branch name + current failing checks summary + unaddressed comments summary
- `metadata`: `{"repo": "factify-inc/mono", "pr": 1234, "branch": "noamsto/pl-344-…", "url": "https://github.com/…"}`

## Step 4: Dispatch

Spawn teammates **in a single message, multiple Agent tool calls in parallel**, up to `--concurrency`. Hold the rest unassigned — idle teammates will claim them.

Each teammate spawn:

- `subagent_type`: `general-purpose`
- `team_name`: the team you just created
- `name`: `shepherd-<repo-slug>-<PR>` (e.g., `shepherd-mono-1234`)
- `prompt`: see template below

### Teammate prompt template

```
You are a Finish-PRs teammate. Your job: take ONE already-open PR and drive it to CI-green + all-comments-addressed. You do NOT implement new features — you fix CI breakage and respond to review feedback only.

## Your PR
**Repo:** <OWNER/REPO>
**PR:** #<N> — <title>
**URL:** <pr-url>
**Branch:** <branch-name>

## Setup

1. Worktree on the PR branch with worktrunk:
   ```bash
   WTPATH=$(wt switch --create <branch-name> --no-cd --format json -y | jq -r '.path')
   cd "$WTPATH"
   gh pr checkout <N> --repo <OWNER/REPO>
   git pull --ff-only
   ```
   `wt switch` is idempotent. The `lazytmux` post-switch hook short-circuits inside Claude so no spurious tmux window spawns.

2. Read the current PR state in one pass:
   ```bash
   gh pr view <N> --repo <OWNER/REPO> --json title,body,statusCheckRollup,reviews,comments,headRefOid
   gh pr checks <N> --repo <OWNER/REPO>
   gh api repos/<OWNER/REPO>/pulls/<N>/comments
   gh api repos/<OWNER/REPO>/issues/<N>/comments
   ```

## Loop

Repeat until exit conditions (below) are met. Cap at **20 iterations**.

### A. CI failures

`gh pr checks <N> --repo <OWNER/REPO>`

- **Ignore "Apps Sanity Gate"** (flaky) for `factify-inc/mono`.
- For every other failing check:
  1. `gh run view <run-id> --log-failed` — read the actual failure
  2. Diagnose root cause. If it's a flake on a re-run-able check (network, transient infra), `gh run rerun <run-id> --failed` once and continue. Don't keep re-running flakes.
  3. Otherwise fix the underlying code, commit (`fix(ci): <what>`), push.

### B. Reviewer comments (bot + human)

Read every comment posted **after the latest commit by me** on this branch (use `headRefOid` + commit author check).

For each comment, decide:

| Comment type | Action |
|--------------|--------|
| Clear, actionable, in-scope | Implement the fix. Commit (`fix(review): <what>`). Push. Reply to the comment thread acknowledging. |
| Trivial unrelated cleanup (one-liner, no behavior change) | Fix it inline. Mention in the reply. |
| **Non-trivial unrelated work** | **Defer.** Reply on the thread: "Out of scope for this PR — tracking separately." If the repo is `factify-inc/*`, create a Linear ticket via the Linear MCP and link it in the reply. If `noamsto/*`, open a GitHub issue and link it. |
| Ambiguous / judgment call | Use your best judgment. Implement what makes sense. Reply explaining what you decided and why. |
| Product/architecture question you genuinely can't answer | Reply on the thread asking the specific question. Mark it pending in your final report — don't loop on it. |
| Already-addressed / stale | Reply briefly noting the commit that addressed it. |

**Reply mechanics:**

- Inline file comments: `gh api -X POST repos/<OWNER/REPO>/pulls/<N>/comments/<comment-id>/replies -f body='…'`
- Top-level PR comments: `gh pr comment <N> --repo <OWNER/REPO> --body '…'`

### C. Push & re-check

After commits, push and wait for CI:

```bash
git push
# Wait for fresh runs to start
sleep 30
gh pr checks <N> --repo <OWNER/REPO>
```

## Defer Rule — when in doubt

Ask yourself: **"Would the user expect this fix to land in *this* PR, or as a follow-up?"**

- Touches the same files / same feature → land it here
- Touches unrelated code that the reviewer noticed in passing → defer with a tracking ticket/issue
- Reviewer literally says "non-blocking" or "follow-up ok" → defer
- Reviewer literally says "must fix before merge" → land it here

When deferring, the reply should be short, polite, and link to the tracking ticket.

## Exit Conditions

Exit when ALL true:

- All CI checks green (except Apps Sanity Gate on `factify-inc/mono`)
- Every comment posted after the latest user commit is either addressed (with a fix) or replied-to (with a deferral or question)
- No new comments arrived between the last push and now

Mark your task **completed** via `TaskUpdate` with a one-line note: "Green: <N commits>, <K deferrals>, <Q open questions>".

## Stuck / blocked

If you hit any of these, mark your task **completed** with a "BLOCKED: …" note, include PR URL, and `SendMessage` the team lead:

- Same fix attempted 3 times with the same failure
- Reviewer comment requires product context you don't have
- Conflict-resolution would touch unrelated files significantly
- You can't reproduce a CI failure locally and the logs are unclear

## Boundaries

- **Never merge.** Never push to main. Never force-push without strong justification (only to fix a bad rebase that the reviewer asked for).
- Stay on this branch. Do not touch other teammates' branches or worktrees.
- Do not message other teammates.
- Do not create new tasks unless deferring (one ticket/issue per deferred comment is fine).
```

## Step 5: Monitor Loop

Poll roughly every 3 minutes. **Don't sleep — messages drive the loop.**

Each iteration:

1. `TaskList` — count completed / in_progress / blocked
2. If a slot opened AND unassigned tasks remain → spawn the next teammate
3. BLOCKED teammates → read their note:
   - Triable: `SendMessage` with missing context, ask them to retry
   - Hard fail: leave it, surface in report
4. Silent `in_progress` >15min → `SendMessage` asking for status

### Exit when

- No `pending` or `in_progress` tasks
- All teammates idle or shut down
- All blockers triaged

**Safety cap:** 60 minutes wall-clock. Past that, snapshot state, surface in report, ask for guidance.

## Step 6: Teardown

For each completed teammate: `SendMessage` `{type: "shutdown_request", reason: "PR shepherding done"}`.

Leave the team file on disk for audit. Don't `TeamDelete` unless asked.

## Step 7: Report

```
## Finish-PRs Complete

**Dispatched:** N PRs
**Wall time:** Xm

### Green (ready for re-review or merge)
- factify-inc/mono#1234 — <title> → <url> (fixed lint, addressed 2 comments)
- noamsto/nix-config#42 — <title> → <url>

### Deferred work (created follow-up tickets)
- factify-inc/mono#1234 → PL-512 "Refactor X" (linked in PR thread)
- factify-inc/mono#1241 → PL-513 "Add metric Y"

### Blocked (need human attention)
- factify-inc/mono#1250 — BLOCKED: <reason>

### Open questions (left as comments on PR)
- factify-inc/mono#1241 — asked reviewer about <X>

### Notes
- <cross-cutting observations>
```

---

## Running this on a schedule

This command is invocation-driven. To shepherd PRs continuously:

- **Local loop** (you're at the machine): `/loop 30m /finish-prs` — re-runs every 30 minutes, scoped to whatever repo you're in. Add `--all` to sweep everything. The `Green` skip in Step 1 makes repeat runs cheap.
- **Remote schedule**: `/schedule` → create a routine that runs `/finish-prs --repo <OWNER/REPO>` (or `--all`) on cron (min interval 1h). The routine has its own git source repo, so always pass the scope explicitly. Needs the Linear MCP connector if any of your PRs are in `factify-inc/*`.

---

## Important Rules

- **Never merge PRs** — same as `/autopilot`
- **No nested teams** — teammates can't `TeamCreate`
- **One PR per teammate** — fresh context per PR, less drift
- **Concurrency cap is real** — >5 simultaneous CI runs against the same repo saturates the runner pool. Default 3 is conservative on purpose.
- **Default scope is the current repo** — auto-detected via `gh repo view`. Use `--all` for cross-repo, `--repo OWNER/REPO` for an explicit override. Unlike `/autopilot` and `/project-autopilot` (which hard-code `factify-inc/mono`), this command supports any repo. Always pass `--repo` to `gh` commands inside teammate prompts.
- **Apps Sanity Gate** flaky exception applies to `factify-inc/mono` only.
- **Defer non-trivial unrelated work, fix trivial unrelated work** — the user's explicit rule. When in doubt, defer with a tracking ticket and a polite reply.
