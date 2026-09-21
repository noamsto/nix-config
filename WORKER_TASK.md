tier: standard
kind: implement
draft: false
engine: claude
model: sonnet
effort: medium
mcp: 
plan: provided
title: Darwin config fails clean-runner eval
Closes #281
dispatcher_pane: %77
crew_dir: /home/noams/nix-config/.git/crew
crew_id: 1789984785-639782
agent_name: sky
worker_id: worker:feat/281-darwin-config-fails-clean-runner-eval#s1789985014-680109
resume: true

## Task

Finish #281 — darwin clean-runner eval failure. A prior worker already wrote the fix; your job is to land it verified.

## State you inherit
- Branch `feat/281-darwin-config-fails-clean-runner-eval` (worktree already exists) has one commit `c53023ab`:
  `fix(ai): stop hookyard's assertion from forcing mac-app-util's trampolineApps` — in `home/ai/hookyard/default.nix`
  the assertion now counts over `removeAttrs config.home.activation ["trampolineApps"]`. Read its commit message: root
  cause is that hookyard's assertion forced every `home.activation.*.data`, and `trampolineApps.data` (mac-app-util,
  darwin) needs an un-substitutable cl-nix-lite `-sources` derivation, so `nix flake check --no-build` fails on a clean store.
- The branch has no PR. main has moved since (e.g. #327 touched hookyard wiring) — rebase onto main and resolve.
- The verification CI run on `scratch/281-verify-fix` NEVER completed: FlakeHub auth failed (`Cannot find netrc credentials
  for https://api.flakehub.com/`) and then the runner shut down. So the fix is unverified on a clean runner.
- Scratch branches `scratch/281-bisect-hm`, `scratch/281-orig-3c2bda62`, `scratch/281-repro`, `scratch/281-verify-fix`
  exist locally + on origin, with worktrees under /tmp/claude-1000/...feat-281.../scratchpad/. Clean them up when done
  (remove worktrees, delete local + remote scratch branches). Use `gtrash put` rather than rm for any file deletion.

## Work
1. Rebase onto main. Confirm the assertion on main still maps over every `home.activation` entry (it does as of fdad44a6,
   `home/ai/hookyard/default.nix` ~line 80) and that no OTHER code on main now forces `trampolineApps.data`.
2. Verify the fix actually addresses the clean-store failure. Preferred: a clean-runner CI verification (fix the scratch
   workflow — drop the FlakeHub/magic-nix-cache step; private inputs may need a token/SSH, see how `refactor/213-oss-split`'s
   `Check` workflow handles it). Acceptable alternative if CI can't fetch private inputs: prove locally that evaluating
   `darwinConfigurations.mbp-m4-pro.config.system.build.toplevel.drvPath` (or the assertions list) no longer forces
   `trampolineApps.data` — e.g. by temporarily overriding `trampolineApps.data` with `throw` in a scratch eval and showing
   the eval succeeds with the fix and throws without it. State in the PR exactly which verification you ran.
3. Open the PR (`Closes #281`), assignee @me. Don't add a Check workflow to main — that belongs to #213.

## Acceptance
- PR open against main, rebased, CI green, with a stated, non-vacuous verification that the fix no longer forces trampolineApps.data.
- Scratch branches/worktrees cleaned up.
