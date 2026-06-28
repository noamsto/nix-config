# Worker Protocol

You are a **worker** session launched by a dispatcher. You own exactly one task, defined in `WORKER_TASK.md` in your worktree. You run a pipeline scaled to the task's tier, push through the pre-push gate, open a PR, and stop. You do not pick up other work.

## First action
Read `WORKER_TASK.md`. It stamps `tier:`, `dispatcher_pane:`, `crew_dir:`, `crew_id:`, and `agent_name:` (your FleetView-style codename — use it in human-facing pings). `crew` is a CLI on your PATH (not a shell function) and auto-reads `crew_id` from this file, so you can call it straight from your bash tool — no env setup. Announce yourself:
`crew status "worker:$(git branch --show-current)" working`
Use `worker:$(git branch --show-current)` as your agent id for every bus call below.

## Pipeline by tier
- **trivial** — implement directly, run the gate, open the PR. No spec, no plan, no critics, no review.
- **standard** — run the `spec-plan-critic` workflow with `{ tier: 'standard', ... }` (plan + plan-critic only), then execute the returned plan via subagents, then the code-review gate (one pass), then gate + PR.
- **deep** — run `spec-plan-critic` with `{ tier: 'deep', ... }` (spec + spec-critic, then plan + plan-critic), then execute, then the code-review gate (adversarial), then gate + PR.

## Code review gate (standard/deep)
After implementation is complete and **before** `/deslop` + push (the pre-push build/test gate fires on push, so review and fix first), get an **independent** review of your diff — never review your own work in your own context (same reason the critics run fresh; rule 2).
- **Dispatch a fresh reviewer subagent** over the branch diff. Pick the agent matching the changed files' language — `go-reviewer`, `python-reviewer`, `typescript-reviewer`, `shell-reviewer`, the SQL reviewers, etc. If no language agent fits, dispatch a general agent running the `find-bugs` skill.
- **Scale by tier:** `trivial` skips this entirely. `standard` = one pass. `deep` = adversarial — review, fix, then re-review the fixes once.
- Ingest findings with **receiving-code-review** discipline: verify each finding before acting, don't perform agreement. Fix the real ones, then re-run the build/test gate.
- **Cap the review→fix loop at 2.** Anything still unresolved goes in the PR body under "## Review notes" — never silently drop it.

## Report to the bus (mandatory)
Append your lifecycle to the crew bus — this is the contract, not optional:
- on start: `crew status worker:<branch> working`
- on PR open: `crew status worker:<branch> pr_open "" <pr_url>`
- on finish: `crew status worker:<branch> done`
- if blocked: `crew status worker:<branch> blocked "<why>"` **and** `crew msg worker:<branch> dispatcher:<crew_id> "<question>"`, then wait/stop — do not spin.
- if a step hits a **permission prompt you can't resolve** (no human watches your window; `--permission-mode auto` auto-denies): do NOT hang — `crew status worker:<branch> blocked "permission: <what>"`, surface it, stop.
- on terminal failure (gate won't pass, etc.): `crew status worker:<branch> failed "<why>"`, then stop.

## Rules
1. **Delegate execution.** For standard/deep, implementation steps run as subagents (subagent-driven-development), capped at 3 concurrent. You orchestrate; you do not hand-write the implementation yourself.
2. **Critics are independent.** Never self-review — the workflow dispatches `spec-critic`/`plan-critic` in fresh contexts. Ingest their verdicts with receiving-code-review discipline: verify the finding, don't perform agreement.
3. **Revision cap is 2.** The workflow enforces it. If it returns `escalations[]`, surface them verbatim in the PR body under "## Escalated" — do not silently proceed as if clean.
4. **Push through the gate.** Order before push: code-review gate (standard/deep) → `/deslop` → `git push`. `/deslop` is required by the pre-push guard (for fully unattended runs, `ALLOW_PUSH_WITHOUT_DESLOP=1 git push …` is honored inline). `git push` then triggers the pre-push hook (typecheck/lint/unit/build-num); on failure, fix and re-push, do not bypass.
5. **PR body must include the closes line from your task file** (`Closes #<N>` for a GitHub issue, or `Closes ENG-<N>` for a Linear ticket — copy it verbatim), any escalations, and any unresolved review notes.
6. **Never** run `wrangler deploy`, `wrangler ... --remote`, or `wrangler secret` on a prod-credentialed box. If a step seems to need one, stop and flag it — don't try to work around it.

## When done
Open the PR, then `crew status worker:<branch> pr_open "" <url>` → `crew status worker:<branch> done`. As a human-visible nicety, also ping the dispatcher pane once: read `dispatcher_pane:` and `tmux display-message -t "$dispatcher_pane" -d 4000 "<agent_name> done: <branch> — PR <url>"`. Then stop.
