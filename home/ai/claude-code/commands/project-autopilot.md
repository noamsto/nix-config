---
description: "Fan out /autopilot across a Linear project: one teammate per ticket → PR per ticket"
argument-hint: "[PROJECT-ID-OR-NAME] [--limit N] [--concurrency N] [--filter <status|label>]"
---

# Project Autopilot: Multi-Ticket Fan-Out

You are the **team lead**. You select a batch of Linear tickets from a project, spawn one teammate per ticket, and each teammate runs `/autopilot TICKET-ID` end-to-end in its own worktree. You coordinate; you do not implement.

**Argument:** `$ARGUMENTS`

Parse the args:
- Positional: Linear project ID or name (interactive picker if omitted)
- `--limit N` — max tickets to dispatch this run (default: 5)
- `--concurrency N` — max teammates running simultaneously (default: 3)
- `--filter <expr>` — extra Linear filter (e.g., `label:backend`, `priority:high`)
- `--dry-run` — show the batch and exit without spawning anything

---

## Step 1: Project Selection

**If a project ID/name was given:** fetch it from Linear, verify it exists, note the team and member roster.

**If not:** list my active Linear projects (status: in-progress or planned), present numbered, ask which one.

## Step 2: Ticket Discovery

Query Linear for tickets in the project that match **all** of:
- Status: `Todo` (or backlog if `--filter status:backlog`)
- Assignee: me (override with `--filter assignee:@all`)
- No open PR already linked (skip tickets with `branch` field pointing at an open PR)
- Plus any user-supplied `--filter`

Cap to `--limit`. Sort by priority desc, then ticket ID asc.

## Step 3: Pre-Flight & Confirmation

Present the batch as a markdown table. **Always pause here** — this is higher blast-radius than single-ticket autopilot.

```
## Project Autopilot Plan

**Project:** <name>
**Concurrency:** N teammates at once
**Tickets to dispatch:** M of total available

| # | Ticket | Title | Priority | Labels | Size guess |
|---|--------|-------|----------|--------|------------|
| 1 | PL-344 | ... | High | backend | S |
| 2 | PL-351 | ... | Med | api | M |
...

Proceed? Any tickets to drop?
```

Wait for user confirmation before continuing. If `--dry-run`, stop here.

### Size guess

Cheap heuristic from ticket body — count distinct deliverables, presence of "and"/"also"/checklists. Mark **L** (large) tickets — those will be broken down by their teammate's `/autopilot` invocation (Step 2 of autopilot covers that).

## Step 4: Team Setup

**Pre-flight:** confirm `teammateMode` in `~/.claude/settings.json` is `"auto"` or `"tmux"` (not `"in-process"`) so each teammate gets its own tmux pane with live Claude TUI. If unset, default is `auto` which detects tmux automatically.

Create the team with `TeamCreate`:
- `team_name`: `proj-<linear-project-slug>-<YYYYMMDD-HHMM>`
- `description`: "Fan-out across <project-name>: tickets <PL-XXX, PL-YYY, ...>"
- `agent_type`: `lead`

Create one task per ticket with `TaskCreate`:
- `subject`: `<TICKET-ID>: <ticket title>`
- `description`: Full ticket body + URL + Linear branch name + any acceptance criteria
- `metadata`: `{"ticket_id": "PL-344", "branch": "noamsto/pl-344-...", "linear_url": "..."}`

## Step 5: Dispatch

Spawn teammates **in a single message, multiple Agent tool calls in parallel**, up to `--concurrency`. Hold the rest of the tasks unassigned — idle teammates will claim them.

Each teammate spawn:
- `subagent_type`: `general-purpose`
- `team_name`: the team you just created
- `name`: `worker-<TICKET-ID>` (e.g., `worker-PL-344`)
- `isolation`: omit (worktree is created by `/autopilot` itself, not by the Agent tool)
- `prompt`: see template below

**What you see:** because `teammateMode` is `auto`/`tmux`, each teammate opens as its own tmux split-pane in your current window, running a live Claude Code TUI you can click into to watch or interrupt. Panes auto-close when the teammate is shut down or the lead exits.

### Teammate prompt template

```
You are a Project Autopilot teammate. Your job: take ONE Linear ticket from start to merge-ready PR.

## Your ticket
**ID:** <TICKET-ID>
**Title:** <title>
**URL:** <linear-url>
**Branch:** <branch-name>

## Your task
Run `/autopilot <TICKET-ID>` exactly. Do not improvise — the slash command has the full workflow.

Repo: `factify-inc/mono`. Work in your own worktree (`/autopilot` creates it via worktrunk).

## Reporting
- When PR is open, CI green, no unaddressed reviewer comments → mark your task **completed** via TaskUpdate. Include the PR URL in the completion note.
- If you hit a hard blocker after 3 attempts on the same problem → mark task **completed** with status note "BLOCKED: <reason>", PR URL if any, and SendMessage the team lead.
- Never merge the PR. Never push to main.
- Stay in your own branch — do not touch other teammates' branches or worktrees.

## Boundaries
- Do not message other teammates unless the task explicitly involves coordination.
- Do not create new tasks unless `/autopilot` breaks your ticket into sub-tickets (then create one task per sub-ticket).
```

## Step 6: Monitor Loop

Poll roughly every 3 minutes. **Don't sleep — let messages drive the loop.** Teammates auto-deliver messages when they complete or escalate.

Each loop iteration:
1. `TaskList` — check completed vs. in-progress vs. blocked
2. If a teammate slot opened (someone completed/blocked) AND unassigned tasks remain → spawn the next teammate (same prompt template)
3. If a teammate reports BLOCKED → read their note, decide:
   - Triable: SendMessage with the missing context, ask them to retry
   - Hard fail: leave it, surface in final report
4. If a teammate has been silent and `in_progress` for >20 min on the same task → SendMessage asking for status

### Exit when all of:
- No `pending` or `in_progress` tasks remain
- All teammates idle or shut down
- All blockers triaged

**Safety cap:** 90 minutes wall-clock for the whole batch. Past that, snapshot the state and ask for guidance.

## Step 7: Teardown

For each completed teammate: SendMessage with `{type: "shutdown_request", reason: "batch complete"}`.

Once all teammates have responded with shutdown approval, the team is dormant. Leave the team file on disk for audit — don't `TeamDelete` unless the user asks.

## Step 8: Report

```
## Project Autopilot Complete

**Project:** <name>
**Dispatched:** N tickets
**Wall time:** Xm

### PRs opened (CI green, awaiting your review)
- [PL-344] <title> → <pr-url>
- [PL-351] <title> → <pr-url>

### Blocked (need human attention)
- [PL-360] <title> — BLOCKED: <reason> (PR: <url-or-none>)

### Skipped (pre-flight)
- [PL-372] dropped during confirmation step

### Notes
- <any cross-cutting concerns the lead noticed during coordination>
```

---

## Important Rules

- **Never merge any PR** — same as `/autopilot`
- **No nested teams** — teammates cannot `TeamCreate`. If a teammate's ticket is too large, it breaks into sub-tickets via Linear, not into a nested team. The sub-tickets land in this run's task list or a follow-up run.
- **One ticket per teammate** — don't reuse a teammate for a second ticket. A new teammate per ticket = fresh context, less drift.
- **Worktree isolation is per teammate, not per task** — relies on unique Linear branch names per ticket. If two tickets accidentally share a branch name, abort and surface.
- **Concurrency cap is real** — `wt switch --create` is filesystem-safe in parallel, but >5 simultaneous CI runs against the same repo may saturate the runner pool. Start small.
- **Repo is `factify-inc/mono`** — applies to all `gh` calls inside teammate autopilot runs.
- **Apps Sanity Gate** is flaky — same exception as `/autopilot`.
