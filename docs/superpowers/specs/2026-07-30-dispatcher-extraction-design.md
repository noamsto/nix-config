# Extracting the dispatcher harness into `noamsto/dispatcher`

**Date:** 2026-07-30
**Status:** design, approved for planning

## Problem

The dispatcher harness — crew bus, worker scaffolder, protocols, launcher, and the
fan-out commands — lives inside `nix-config` and is spread across eight directories.
Four things follow from that:

1. **Slow edit→test loop.** Protocol and script edits need `nh home switch` before
   they take effect. Protocol iteration is the bulk of the work on this system.
2. **Context pollution.** A session working on the dispatcher loads all of
   `nix-config` — every host, module, and unrelated skill.
3. **No tests.** ~1150 lines of shell with no test suite; `shellcheck` runs only as a
   side effect of `writeShellApplication`.
4. **Not shareable.** It is a general agent-orchestration harness trapped in a
   personal NixOS config.

## Non-goals

- Rewriting any shell in Go. Considered and rejected for this change; revisit from
  inside the new repo.
- Capability parity for codex/cursor workers (critic pipeline, review gate). Those
  engines stay *process-light* exactly as `WORKER_PROTOCOL.md` already documents.
- Converging the autopilot family onto the crew bus. That is iteration #1 in the new
  repo, not part of the move.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Repo name | `noamsto/dispatcher` | Zero renaming churn — protocol filenames, slash command, launcher and 27 design docs already use the word. `crew` was rejected: [CrewAI](https://github.com/crewaiinc/crewai) owns that vocabulary publicly in the same niche. |
| `crew` boundary | Ships in the same repo | crew and dispatch co-evolve; two flake inputs would mean version skew for no gain. `crew` stays a clean internal boundary, splittable later. |
| Language | Shell, extracted verbatim | Behaviour-preserving move so any breakage is provably the move. A Go port is a separate decision. |
| Distribution | CC plugin + codex plugin + cursor loose files + nix flake | Matches `aeye`'s `adapters/` layout, already proven across two engines. |
| Scope | Core + `/dispatcher`, `/autopilot`, `/finish-prs`, `/project-autopilot` + critic pipeline | Keeps the lead→worker caller/callee pair together; puts every fan-out implementation in one repo. |
| Multi-engine | Packaging parity now, capability parity later | See "Engine surfaces". |

## Engine surfaces

Established by inspection of `aeye`'s adapters plus vendor docs:

| Surface | Claude Code | Codex | Cursor |
|---|---|---|---|
| Packaging format | plugin `.claude-plugin/` | plugin `.codex-plugin/` | **none** — loose files |
| Custom slash commands | yes | **no** — built-in only; custom prompts deprecated in favour of skills | yes |
| Skills | yes | yes (`$name` or `/skills`) | yes |
| Subagents | yes | **no** (not expressible in a codex plugin) | yes, different model |
| Hooks | yes | yes | yes (in-process runner since Jan 2026) |

Three consequences drive the layout:

- The four commands ship as **commands** on Claude Code and cursor, and as **skills**
  on codex. One shared markdown body in `adapters/core/commands/`, three delivery
  shapes. Generation is a committed-output script (`scripts/gen-adapters.sh`), not a
  Nix build step: the adapter trees must be real files in the repo so a non-Nix user
  can clone and install. CI guards drift by regenerating and asserting
  `git diff --exit-code`.
- Cursor's adapter is loose files written by the Home Manager module into
  `~/.cursor/{rules,commands}/`, mirroring the existing `shared-conventions.mdc`
  pattern. A `.mdc` rule is silently ignored without `alwaysApply: true` frontmatter.
- Codex plugins must be installed as a **real directory** under
  `~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/`. A symlinked tree
  reports "installed, enabled" in `codex plugin list` while its skills never reach the
  model. This is the trap `aeye`'s `activation.aeyeCodexPlugin` already works around
  with `cp -rL` + `chmod -R u+w`.

## Repository layout

```
noamsto/dispatcher
├── adapters/
│   ├── core/                        # engine-neutral
│   │   ├── crew.sh                  # 833 L, git-backed bus
│   │   ├── dispatch.sh              # 304 L, worker scaffolder
│   │   ├── dispatcher.sh            # ~130 L, launcher (ported from fish)
│   │   ├── dispatch-notify.sh       # 40 L, SessionEnd hook
│   │   ├── protocols/
│   │   │   ├── DISPATCHER_PROTOCOL.md
│   │   │   ├── WORKER_PROTOCOL.md
│   │   │   └── dispatch-orchestration.md
│   │   └── commands/                # shared bodies, generated into each adapter
│   │       ├── dispatcher.md
│   │       ├── autopilot.md
│   │       ├── finish-prs.md
│   │       └── project-autopilot.md
│   ├── claude-code/plugin/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── commands/                # 4, generated
│   │   ├── agents/                  # spec-critic.md, plan-critic.md
│   │   ├── skills/spec-plan-critic/
│   │   ├── workflows/spec-plan-critic.js
│   │   └── hooks/hooks.json
│   ├── codex/
│   │   ├── plugin/
│   │   │   ├── .codex-plugin/plugin.json
│   │   │   ├── skills/              # 4 commands AS skills + spec-plan-critic
│   │   │   └── hooks/hooks.json
│   │   └── .agents/plugins/marketplace.json
│   └── cursor/                      # no plugin format — loose files
│       ├── rules/                   # alwaysApply: true
│       └── commands/                # 4, generated
├── tests/                           # bats
├── docs/superpowers/                # 27 migrated specs + plans
├── flake.nix                        # packages + homeManagerModules.default
└── .github/workflows/ci.yml         # shellcheck + bats
```

## What moves

**Shell (~1307 L)** — `crew.sh` (833), `dispatch.sh` (304), `dispatch-notify.sh` (40),
and the `dispatcher` fish function (~130, from `home/terminal/fish/default.nix`)
ported to `dispatcher.sh`. Counts as of `15b818c5`; both files change often, so
verify before relying on them.

**Protocols (482 L)** — `DISPATCHER_PROTOCOL.md` (217), `WORKER_PROTOCOL.md` (145),
`dispatch-orchestration.md` (120).

**Commands (760 L)** — `dispatcher.md` (67), `autopilot.md` (218), `finish-prs.md`
(304), `project-autopilot.md` (171).

**Critic pipeline** — `skills/spec-plan-critic/SKILL.md`,
`workflows/spec-plan-critic.js`, `agents/spec-critic.md`, `agents/plan-critic.md`.
Verified referenced by nothing outside the dispatcher; `WORKER_PROTOCOL.md` mandates
them, and the tier system is *defined* as which critics run.

**Nix** — the `crew`, `dispatch`, `dispatch-notify` derivations, the `SessionEnd` hook,
and `DISPATCH_PROFILE` from `home/ai/claude-code/default.nix`.

**Docs** — the ~27 dispatcher/crew specs and plans under `docs/superpowers/`.

## What stays in nix-config

`/pr-review` and all `*-reviewer` agents, `find-bugs`, `/deslop`, `/commit`, `/push`,
the codex `worker` MCP profile (`~/.codex/worker.config.toml` — codex-CLI territory,
declared a module prerequisite), and cursor's `mcp.json`. `WORKER_PROTOCOL.md`
references the language reviewers and `/deslop` opportunistically; they remain ambient
capabilities the worker uses if present, not harness components.

## Forced behaviour changes

Three, all consequences of leaving `nix-config`. Everything else is byte-identical.

### 1. Protocol path resolution

`dispatch.sh` hardcodes `~/nix-config/home/ai/claude-code/WORKER_PROTOCOL.md` in three
launch strings (claude, codex, cursor); the fish launcher hardcodes
`DISPATCHER_PROTOCOL.md`. Both become a build-time-substituted store path, overridable
via `DISPATCHER_PROTOCOL_DIR`.

**This override is the dev loop.** Point it at a checkout and protocol edits take
effect on the next `dispatch` with no rebuild. Given that protocol iteration is most of
the work on this system, this is the highest-value single change in the extraction.

### 2. fish launcher → bash script

Nothing in the function is fish-bound. `$fish_pid` → `$$` is equivalent: the script
blocks on the foreground agent, so its liveness tracks the session the same way, which
is what the stale-reclaim key needs.

**One accepted regression:** `set -gx CREW_ID` currently exports into the interactive
shell, so a later `crew status` in the same terminal inherits the id. A script can only
export to its children. Mitigation: print the id at launch — `/dispatcher` already
instructs the agent to note it literally, because Claude Code's Bash tool does not
persist env between calls either.

### 3. `DISPATCH_PROFILE` → module option

Becomes `programs.dispatcher.profile = "work" | "personal"`, set from
`osConfig.profile`. Same work-profile gate on codex/cursor engines, now an explicit
module contract rather than an ambient env var. Readers: `dispatch.sh` and the
launcher.

## Command namespacing

Claude Code and codex plugin content is namespaced, so `/autopilot` becomes
`/dispatcher:autopilot` and `$dispatcher:autopilot` respectively. Accepted — it groups
the commands and avoids collisions for external users. One string needs updating:
`project-autopilot.md` instructs teammates to run `/autopilot TICKET-ID`.

## Testing

`shellcheck` already runs at build via `writeShellApplication`; CI makes it a gate
rather than a side effect.

`bats` coverage concentrates on `crew.sh`, which is pure git plumbing against
`.git/crew/` and therefore genuinely unit-testable with a temp repo per test:

- `crew id` — mints without a git repo (ordering matters; it runs before the repo check)
- `crew register` / `deregister` — non-exclusive, N crews per repo, idempotent re-register
- `msg` / `inbox` — filtering, including that `metrics:<crew>` does **not** match a
  dispatcher's `to==dispatcher:<crew>`/`*` watch filter
- stale entry handling

`dispatch.sh` is mostly `tmux send-keys`; test argument parsing, the work-profile
engine gate, and the composed launch strings with `tmux` stubbed. The existing empty
`crew-smoke` repo becomes the integration fixture. `lazytmux`'s `tests/*.bats` is the
in-house pattern to follow.

## Migration sequence

Behaviour-preserving throughout; each step independently verifiable.

1. Scaffold `noamsto/dispatcher` — flake, devshell, direnv, CI, `adapters/core`.
2. Move shell + protocols verbatim. Add `DISPATCHER_PROTOCOL_DIR` and substitute the
   four hardcoded paths.
3. Port the fish launcher to `dispatcher.sh`.
4. Build the three adapters and the command generator.
5. Add `homeManagerModules.default` — binaries on PATH, `--plugin-dir` for Claude Code,
   `cp -rL` activation for codex, `home.file` for cursor.
6. Wire into `nix-config` as a flake input; delete the moved files. `.claude/commands`
   stays a whole-directory symlink — the four moved files simply leave the source
   directory and `/pr-review`, `/commit`, `/push` remain.
7. Migrate the 27 design docs.
8. Add bats coverage.

Verification after each step: a real `dispatcher` launch that dispatches one trivial
worker to a PR on `crew-smoke`, on each of the three engines.

## Known risk

Step 6 is the only irreversible one — it deletes from `nix-config` while the new repo
is a live flake input. Land steps 1–5 and verify on a branch with an
`override-input` pointing at a local checkout (the pattern already used for the
lazytmux darwin port) before deleting anything.

## Iteration #1 (not this change)

Replace the Claude Code teammate fan-out in `finish-prs` and `project-autopilot` with
**crew-bus fan-out**. The crew bus is already the engine-neutral equivalent of CC
teammates — git-backed files plus tmux windows, nothing Claude-specific — so this both
kills the duplicate fan-out architecture and is the only way those two commands can run
on codex or cursor at all. Multi-engine support is the forcing function that makes this
necessary rather than merely tidy.
