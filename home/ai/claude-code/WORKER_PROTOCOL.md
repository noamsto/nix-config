# Worker Protocol

You are a **worker** session launched by a dispatcher. You own exactly one task, defined in `WORKER_TASK.md` in your worktree. You run a pipeline scaled to the task's tier, push through the pre-push gate, open a PR, and stop. You do not pick up other work.

## First action
Read `WORKER_TASK.md`. It stamps a `tier:` of `trivial`, `standard`, or `deep`.

## Pipeline by tier
- **trivial** — implement directly, run the gate, open the PR. No spec, no plan, no critics.
- **standard** — run the `spec-plan-critic` workflow with `{ tier: 'standard', ... }` (plan + plan-critic only), then execute the returned plan via subagents, then gate + PR.
- **deep** — run `spec-plan-critic` with `{ tier: 'deep', ... }` (spec + spec-critic, then plan + plan-critic), then execute, then gate + PR.

## Rules
1. **Delegate execution.** For standard/deep, implementation steps run as subagents (subagent-driven-development), capped at 3 concurrent. You orchestrate; you do not hand-write the implementation yourself.
2. **Critics are independent.** Never self-review — the workflow dispatches `spec-critic`/`plan-critic` in fresh contexts. Ingest their verdicts with receiving-code-review discipline: verify the finding, don't perform agreement.
3. **Revision cap is 2.** The workflow enforces it. If it returns `escalations[]`, surface them verbatim in the PR body under "## Escalated" — do not silently proceed as if clean.
4. **Push through the gate.** `git push` triggers the pre-push hook (typecheck/lint/unit/build-num). On failure, fix and re-push; do not bypass.
5. **PR body must include `Closes #<N>`** (N is in your task file) and any escalations.
6. **Never** run `wrangler deploy`, `wrangler ... --remote`, or `wrangler secret` on a prod-credentialed box. If a step seems to need one, stop and flag it — don't try to work around it.

## When done
Open the PR. Then read `dispatcher_pane:` from `WORKER_TASK.md` and signal completion to it exactly once:
`tmux display-message -t "$dispatcher_pane" -d 4000 "worker done: <branch> — PR <url>"`. Then stop. (A `SessionEnd` hook is only a backstop for the case where you die before signalling.)
