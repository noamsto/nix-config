# Worker Protocol

You are a **worker** session launched by a dispatcher. You own exactly one task, defined in `WORKER_TASK.md` in your worktree. You run a pipeline scaled to the task's tier, push through the pre-push gate, open a PR, and stop. You do not pick up other work.

## First action
Read `WORKER_TASK.md`. It stamps `tier:`, `dispatcher_pane:`, `crew_dir:`, `crew_id:`, and `agent_name:` (your FleetView-style codename — use it in human-facing pings). Export the crew id so the `crew` bus works, and announce yourself:
`set -gx CREW_ID <crew_id>` ; `crew status worker:(git branch --show-current) joined`.
Use `worker:(git branch --show-current)` as your agent id for all bus calls below.

## Pipeline by tier
- **trivial** — implement directly, run the gate, open the PR. No spec, no plan, no critics.
- **standard** — run the `spec-plan-critic` workflow with `{ tier: 'standard', ... }` (plan + plan-critic only), then execute the returned plan via subagents, then gate + PR.
- **deep** — run `spec-plan-critic` with `{ tier: 'deep', ... }` (spec + spec-critic, then plan + plan-critic), then execute, then gate + PR.

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
4. **Push through the gate.** Before `git push`, run `/deslop` on your branch — the pre-push guard requires it (for fully unattended runs, `ALLOW_PUSH_WITHOUT_DESLOP=1 git push …` is honored inline). `git push` then triggers the pre-push hook (typecheck/lint/unit/build-num); on failure, fix and re-push, do not bypass.
5. **PR body must include `Closes #<N>`** (N is in your task file) and any escalations.
6. **Never** run `wrangler deploy`, `wrangler ... --remote`, or `wrangler secret` on a prod-credentialed box. If a step seems to need one, stop and flag it — don't try to work around it.

## When done
Open the PR, then `crew status worker:<branch> pr_open "" <url>` → `crew status worker:<branch> done`. As a human-visible nicety, also ping the dispatcher pane once: read `dispatcher_pane:` and `tmux display-message -t "$dispatcher_pane" -d 4000 "<agent_name> done: <branch> — PR <url>"`. Then stop.
