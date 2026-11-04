# Cursor dispatch engine: indexing stall + bus stall detector (#103)

> **Correction (2026-07-26).** Part A below is misdiagnosed — indexing was never
> the cause. `cursor-agent -p --output-format text` prints *only* the final
> message, so a cursor worker emits nothing to its pane for the entire task, and
> the Part B watchdog (which infers liveness from pane output) then failed every
> cursor worker at grace+stall. Evidence: on the `eng-7531` dispatch the worker
> posted a healthy `working` **18s** after launch — it launched, read the
> protocol, and started work — and the watchdog still posted `stalled: no output
> for 300s` eight minutes later. The `cursor-retrieval: tracing to …` line that
> anchored the original diagnosis comes from the in-process `file_service` NAPI
> module, not the `crepectl` indexed-grep path that `CURSOR_CLI_INDEXED_GREP=0`
> gates, and it only appears under the mono devshell env — noise, not a stall.
> The flags are real and are kept (skips a merkle index build, parity with
> claude/codex), but the actual fix is `--output-format stream-json | jq`.

## Problem

`dispatch --agent cursor` on a large monorepo hangs at startup:
`cursor-agent` prints `cursor-retrieval: tracing to '…'` and then produces no
output for 9+ minutes — its codebase retrieval/indexing pass chokes on the repo
size and never reaches the task. On the crew bus the worker looks alive
(`working` + climbing `age_s`), so the stall is invisible and the dispatcher
can't auto-recover.

## Fix (two parts)

### A. Root cause — disable cursor indexing (dispatch.sh)

`cursor-agent` has hidden knobs that suppress the retrieval/indexing subsystems:

- `--disable-indexing` — skip the merkle codebase index build.
- `--disable-codebase-ref` — skip the semantic codebase reference (+ `read_lints`).
- `CURSOR_CLI_INDEXED_GREP=0` — force plain grep instead of the indexed-grep
  path (the `crepectl` / `cursor-retrieval` subprocess that hung).

The cursor worker launch now sets all three. This is **parity with claude/codex
workers**, which have no semantic index either — they read + grep — so it's no
real capability loss for a dispatched worker.

Verified empirically (cursor-agent 2026.07.20): with the flags, no
`cursor-retrieval` line appears, and a codebase search still resolves correctly
via the plain-grep fallback.

### B. Defense-in-depth — engine-agnostic stall watchdog

The bus is blind to a hung worker: a worker posts `working` once at launch then
nothing until a terminal state, and the SessionEnd `exited` backstop only fires
when a session actually *ends* — a wedged agent never ends. So no event is
emitted and the dispatcher's `crew watch` never wakes.

New `crew stall-watch <branch> --pane <id>` subcommand, spawned detached by
`dispatch` per worker (all engines). It automates the manual `tmux capture-pane`
that confirmed #103: after a grace period, within a bounded startup `--window`,
if the pane's visible output doesn't change for `--stall` seconds and the worker
hasn't reached a non-`working` state, it posts
`crew status worker:<branch> failed "stalled: …"` → `crew watch` wakes the
dispatcher, which recovers per DISPATCHER_PROTOCOL rule 4 (kill window +
re-dispatch / intervene / drop).

Design choices:

- **Pane-output, not bus-age.** A deep worker can be legitimately silent on the
  bus for a long time, so age alone can't distinguish stalled from slow. Pane
  output is the real liveness signal (it's what confirmed the bug manually).
- **Windowed to startup.** The observed hang is a startup/indexing stall;
  bounding the watchdog to the first `--window` seconds avoids killing a long,
  legitimately-quiet execute stage later.
- **`_progressed` gate.** Any status past the launch `working` (progress,
  deliberate `blocked`, or terminal) proves the agent is alive → stop watching.
- **Testable seam.** `CREW_STALL_SAMPLE_CMD` overrides the pane sampler (stdout =
  output, exit code = pane liveness) so the loop is unit-tested without tmux.

Defaults: `--grace 45 --stall 300 --window 900 --interval 15`.

## Files

- `home/ai/claude-code/dispatch.sh` — cursor launch flags/env (A); spawn
  `nohup crew stall-watch … &` after launch (B).
- `home/ai/claude-code/crew.sh` — `stall-watch` subcommand + usage.
- `home/ai/claude-code/default.nix` — add `pkgs.tmux` to `crew` runtimeInputs.
- `home/ai/claude-code/DISPATCHER_PROTOCOL.md` — note watchdog-emitted `failed`.
- `home/ai/claude-code/dispatch-orchestration.md` — cursor indexing-off note.

## Deploys

`crew`/`dispatch` are `writeShellApplication` PATH binaries → needs
`nh home switch` to activate. Doc edits (read-by-path off main) deploy on merge.

## Verification

- Fix A: live cursor-agent run with the flags — no retrieval pass, search works.
- Watchdog: 6-case shell suite (static→failed, activity→no-fire,
  progressed/blocked→exit, dead-pane→exit, missing-pane→usage) + real-tmux smoke.
- `shellcheck` + `shfmt -i 2` clean; `nh home build .` succeeds.
